/* This file is part of the re::engine::Plugin Perl module.
 * See http://search.cpan.org/dist/re-engine-Plugin/ */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "Plugin.h"

#define __PACKAGE__     "re::engine::Plugin"
#define __PACKAGE_LEN__ (sizeof(__PACKAGE__)-1)

#define REP_HAS_PERL(R, V, S) (PERL_REVISION > (R) || (PERL_REVISION == (R) && (PERL_VERSION > (V) || (PERL_VERSION == (V) && (PERL_SUBVERSION >= (S))))))

#ifndef REP_WORKAROUND_REQUIRE_PROPAGATION
# define REP_WORKAROUND_REQUIRE_PROPAGATION !REP_HAS_PERL(5, 10, 1)
#endif

/* ... Thread safety and multiplicity ...................................... */

#ifndef REP_MULTIPLICITY
# if defined(MULTIPLICITY) || defined(PERL_IMPLICIT_CONTEXT)
#  define REP_MULTIPLICITY 1
# else
#  define REP_MULTIPLICITY 0
# endif
#endif
#if REP_MULTIPLICITY && !defined(tTHX)
# define tTHX PerlInterpreter*
#endif

#if REP_MULTIPLICITY && defined(USE_ITHREADS) && defined(dMY_CXT) && defined(MY_CXT) && defined(START_MY_CXT) && defined(MY_CXT_INIT) && (defined(MY_CXT_CLONE) || defined(dMY_CXT_SV))
# define REP_THREADSAFE 1
# ifndef MY_CXT_CLONE
#  define MY_CXT_CLONE \
    dMY_CXT_SV;                                                      \
    my_cxt_t *my_cxtp = (my_cxt_t*)SvPVX(newSV(sizeof(my_cxt_t)-1)); \
    Copy(INT2PTR(my_cxt_t*, SvUV(my_cxt_sv)), my_cxtp, 1, my_cxt_t); \
    sv_setuv(my_cxt_sv, PTR2UV(my_cxtp))
# endif
#else
# define REP_THREADSAFE 0
# undef  dMY_CXT
# define dMY_CXT      dNOOP
# undef  MY_CXT
# define MY_CXT       rep_globaldata
# undef  START_MY_CXT
# define START_MY_CXT STATIC my_cxt_t MY_CXT;
# undef  MY_CXT_INIT
# define MY_CXT_INIT  NOOP
# undef  MY_CXT_CLONE
# define MY_CXT_CLONE NOOP
#endif

/* --- Helpers ------------------------------------------------------------- */

/* ... Thread-safe hints ................................................... */

typedef struct {
 SV  *comp;
 SV  *exec;
#if REP_WORKAROUND_REQUIRE_PROPAGATION
 I32  requires;
#endif
} rep_hint_t;

#if REP_THREADSAFE

#define PTABLE_VAL_FREE(V) { \
 rep_hint_t *h = (V);        \
 SvREFCNT_dec(h->comp);      \
 SvREFCNT_dec(h->exec);      \
 PerlMemShared_free(h);      \
}

#define pPTBL  pTHX
#define pPTBL_ pTHX_
#define aPTBL  aTHX
#define aPTBL_ aTHX_

#include "ptable.h"

#define ptable_store(T, K, V) ptable_store(aTHX_ (T), (K), (V))
#define ptable_free(T)        ptable_free(aTHX_ (T))

#define MY_CXT_KEY __PACKAGE__ "::_guts" XS_VERSION

typedef struct {
 ptable *tbl;
 tTHX    owner;
} my_cxt_t;

START_MY_CXT

STATIC SV *rep_clone(pTHX_ SV *sv, tTHX owner) {
#define rep_clone(S, O) rep_clone(aTHX_ (S), (O))
 CLONE_PARAMS  param;
 AV           *stashes = NULL;
 SV           *dupsv;

 if (SvTYPE(sv) == SVt_PVHV && HvNAME_get(sv))
  stashes = newAV();

 param.stashes    = stashes;
 param.flags      = 0;
 param.proto_perl = owner;

 dupsv = sv_dup(sv, &param);

 if (stashes) {
  av_undef(stashes);
  SvREFCNT_dec(stashes);
 }

 return SvREFCNT_inc(dupsv);
}

STATIC void rep_ptable_clone(pTHX_ ptable_ent *ent, void *ud_) {
 my_cxt_t   *ud = ud_;
 rep_hint_t *h1 = ent->val;
 rep_hint_t *h2;

 if (ud->owner == aTHX)
  return;

 h2           = PerlMemShared_malloc(sizeof *h2);
 h2->comp     = rep_clone(h1->comp, ud->owner);
 SvREFCNT_inc(h2->comp);
 h2->exec     = rep_clone(h1->exec, ud->owner);
 SvREFCNT_inc(h2->exec);
#if REP_WORKAROUND_REQUIRE_PROPAGATION
 h2->requires = h1->requires;
#endif

 ptable_store(ud->tbl, ent->key, h2);
}

STATIC void rep_thread_cleanup(pTHX_ void *);

STATIC void rep_thread_cleanup(pTHX_ void *ud) {
 int *level = ud;

 if (*level) {
  *level = 0;
  LEAVE;
  SAVEDESTRUCTOR_X(rep_thread_cleanup, level);
  ENTER;
 } else {
  dMY_CXT;
  PerlMemShared_free(level);
  ptable_free(MY_CXT.tbl);
 }
}

#endif /* REP_THREADSAFE */

STATIC SV *rep_validate_callback(SV *code) {
 if (!SvROK(code))
  return NULL;

 code = SvRV(code);
 if (SvTYPE(code) < SVt_PVCV)
  return NULL;

 return SvREFCNT_inc_simple_NN(code);
}

STATIC SV *rep_tag(pTHX_ SV *comp, SV *exec) {
#define rep_tag(C, E) rep_tag(aTHX_ (C), (E))
 rep_hint_t *h;
 dMY_CXT;

 h = PerlMemShared_malloc(sizeof *h);

 h->comp = rep_validate_callback(comp);
 h->exec = rep_validate_callback(exec);

#if REP_WORKAROUND_REQUIRE_PROPAGATION
 {
  const PERL_SI *si;
  I32            requires = 0;

  for (si = PL_curstackinfo; si; si = si->si_prev) {
   I32 cxix;

   for (cxix = si->si_cxix; cxix >= 0; --cxix) {
    const PERL_CONTEXT *cx = si->si_cxstack + cxix;

    if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE)
     ++requires;
   }
  }

  h->requires = requires;
 }
#endif

#if REP_THREADSAFE
 /* We only need for the key to be an unique tag for looking up the value later.
  * Allocated memory provides convenient unique identifiers, so that's why we
  * use the hint as the key itself. */
 ptable_store(MY_CXT.tbl, h, h);
#endif /* REP_THREADSAFE */

 return newSViv(PTR2IV(h));
}

STATIC const rep_hint_t *rep_detag(pTHX_ const SV *hint) {
#define rep_detag(H) rep_detag(aTHX_ (H))
 rep_hint_t *h;
 dMY_CXT;

 if (!(hint && SvIOK(hint)))
  return NULL;

 h = INT2PTR(rep_hint_t *, SvIVX(hint));
#if REP_THREADSAFE
 h = ptable_fetch(MY_CXT.tbl, h);
#endif /* REP_THREADSAFE */

#if REP_WORKAROUND_REQUIRE_PROPAGATION
 {
  const PERL_SI *si;
  I32            requires = 0;

  for (si = PL_curstackinfo; si; si = si->si_prev) {
   I32 cxix;

   for (cxix = si->si_cxix; cxix >= 0; --cxix) {
    const PERL_CONTEXT *cx = si->si_cxstack + cxix;

    if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_op_type == OP_REQUIRE
                               && ++requires > h->requires)
     return NULL;
   }
  }
 }
#endif

 return h;
}

STATIC U32 rep_hash = 0;

STATIC const rep_hint_t *rep_hint(pTHX) {
#define rep_hint() rep_hint(aTHX)
 SV *hint;

 /* We already require 5.9.5 for the regexp engine API. */
 hint = Perl_refcounted_he_fetch(aTHX_ PL_curcop->cop_hints_hash,
                                       NULL,
                                       __PACKAGE__, __PACKAGE_LEN__,
                                       0,
                                       rep_hash);

 return rep_detag(hint);
}

REGEXP *
#if PERL_VERSION <= 10
Plugin_comp(pTHX_ const SV * const pattern, const U32 flags)
#else
Plugin_comp(pTHX_ SV * const pattern, U32 flags)
#endif
{
    dSP;
    struct regexp * rx;
    REGEXP *RX;
    I32 buffers;
    re__engine__Plugin re;
    const rep_hint_t *h;

    /* exp/xend version of the pattern & length */
    STRLEN plen;
    char*  exp = SvPV((SV*)pattern, plen);

    /* Our blessed object */
    SV *obj = newSV(0);
    SvREFCNT_inc(obj);
    Newxz(re, 1, struct replug);
    sv_setref_pv(obj, "re::engine::Plugin", (void*)re);

    newREGEXP(RX);
    rx = rxREGEXP(RX);

    re->rx = rx;                   /* Make the rx accessible from self->rx */
    rx->intflags = flags;          /* Flags for internal use */
    rx->extflags = flags;          /* Flags for perl to use */
    rx->engine = RE_ENGINE_PLUGIN; /* Compile to use this engine */

#if PERL_VERSION <= 10
    rx->refcnt = 1;                /* Refcount so we won't be destroyed */

    /* Precompiled pattern for pp_regcomp to use */
    rx->prelen = plen;
    rx->precomp = savepvn(exp, rx->prelen);

    /* Set up qr// stringification to be equivalent to the supplied
     * pattern, this should be done via overload eventually.
     */
    rx->wraplen = rx->prelen;
    Newx(rx->wrapped, rx->wraplen, char);
    Copy(rx->precomp, rx->wrapped, rx->wraplen, char);
#endif

    /* Store our private object */
    rx->pprivate = obj;

    /* Store the pattern for ->pattern */
    re->pattern = (SV*)pattern;
    SvREFCNT_inc(re->pattern);

    /*
     * Call our callback function if one was defined, if not we've
     * already set up all the stuff we're going to to need for
     * subsequent exec and other calls
     */
    h = rep_hint();
    if (h && h->comp) {
        ENTER;    
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(obj);
        PUTBACK;

        call_sv(h->comp, G_DISCARD);

        FREETMPS;
        LEAVE;
    }

    /* If there's an exec callback, store it into the private object so
     * that it will be the one to be called, even if the engine changes
     * in between */
    if (h && h->exec) {
        re->cb_exec = h->exec;
	SvREFCNT_inc_simple_void_NN(h->exec);
    }

    /* If any of the comp-time accessors were called we'll have to
     * update the regexp struct with the new info.
     */

    buffers = rx->nparens;

    Newxz(rx->offs, buffers + 1, regexp_paren_pair);

    return RX;
}

I32
Plugin_exec(pTHX_ REGEXP * const RX, char *stringarg, char *strend,
            char *strbeg, I32 minend, SV *sv, void *data, U32 flags)
{
    dSP;
    I32 matched;
    struct regexp *rx = rxREGEXP(RX);
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    if (self->cb_exec) {
        /* Store the current str for ->str */
        self->str = (SV*)sv;
        SvREFCNT_inc(self->str);

        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv);
        PUTBACK;

        call_sv(self->cb_exec, G_SCALAR);
 
        SPAGAIN;

        SV * ret = POPs;

        if (SvTRUE(ret))
            matched = 1;
        else
            matched = 0;

        PUTBACK;
        FREETMPS;
        LEAVE;
    } else {
        matched = 0;
    }

    return matched;
}

char *
Plugin_intuit(pTHX_ REGEXP * const RX, SV *sv, char *strpos,
                     char *strend, U32 flags, re_scream_pos_data *data)
{
    PERL_UNUSED_ARG(RX);
    PERL_UNUSED_ARG(sv);
    PERL_UNUSED_ARG(strpos);
    PERL_UNUSED_ARG(strend);
    PERL_UNUSED_ARG(flags);
    PERL_UNUSED_ARG(data);
    return NULL;
}

SV *
Plugin_checkstr(pTHX_ REGEXP * const RX)
{
    PERL_UNUSED_ARG(RX);
    return NULL;
}

void
Plugin_free(pTHX_ REGEXP * const RX)
{
    PERL_UNUSED_ARG(RX);
/*
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_free;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
    return;
*/
}

void *
Plugin_dupe(pTHX_ REGEXP * const RX, CLONE_PARAMS *param)
{
    struct regexp *rx = rxREGEXP(RX);
    Perl_croak(aTHX_ "dupe not supported yet");
    return rx->pprivate;
}


void
Plugin_numbered_buff_FETCH(pTHX_ REGEXP * const RX, const I32 paren,
                           SV * const sv)
{
    dSP;
    I32 items;
    SV * callback;
    struct regexp *rx = rxREGEXP(RX);
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_num_capture_buff_FETCH;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(paren)));
        PUTBACK;

        items = call_sv(callback, G_SCALAR);
        
        if (items == 1) {
            SPAGAIN;

            SV * ret = POPs;
            sv_setsv(sv, ret);
        } else {
            sv_setsv(sv, &PL_sv_undef);
        }

        PUTBACK;
        FREETMPS;
        LEAVE;
    } else {
        sv_setsv(sv, &PL_sv_undef);
    }
}

void
Plugin_numbered_buff_STORE(pTHX_ REGEXP * const RX, const I32 paren,
                           SV const * const value)
{
    dSP;
    SV * callback;
    struct regexp *rx = rxREGEXP(RX);
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_num_capture_buff_STORE;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(paren)));
        XPUSHs(SvREFCNT_inc((SV *) value));
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

I32
Plugin_numbered_buff_LENGTH(pTHX_ REGEXP * const RX, const SV * const sv,
                              const I32 paren)
{
    dSP;
    SV * callback;
    struct regexp *rx = rxREGEXP(RX);
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_num_capture_buff_LENGTH;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(paren)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        IV ret = POPi;

        PUTBACK;
        FREETMPS;
        LEAVE;

        return (I32)ret;
    } else {
        /* TODO: call FETCH and get the length on that value */
        return 0;
    }
}


SV*
Plugin_named_buff (pTHX_ REGEXP * const RX, SV * const key, SV * const value,
                   const U32 flags)
{
    return NULL;
}

SV*
Plugin_named_buff_iter (pTHX_ REGEXP * const RX, const SV * const lastkey,
                        const U32 flags)
{
    return NULL;
}

SV*
Plugin_package(pTHX_ REGEXP * const RX)
{
    PERL_UNUSED_ARG(RX);
    return newSVpvs("re::engine::Plugin");
}

#if REP_THREADSAFE

STATIC U32 rep_initialized = 0;

STATIC void rep_teardown(pTHX_ void *root) {
 dMY_CXT;

 if (!rep_initialized || aTHX != root)
  return;

 ptable_free(MY_CXT.tbl);

 rep_initialized = 0;
}

STATIC void rep_setup(pTHX) {
#define rep_setup() rep_setup(aTHX)
 if (rep_initialized)
  return;

 MY_CXT_INIT;
 MY_CXT.tbl   = ptable_new();
 MY_CXT.owner = aTHX;

 call_atexit(rep_teardown, aTHX);

 rep_initialized = 1;
}

#else  /*  REP_THREADSAFE */

#define rep_setup()

#endif /* !REP_THREADSAFE */

STATIC U32 rep_booted = 0;

/* --- XS ------------------------------------------------------------------ */

MODULE = re::engine::Plugin	PACKAGE = re::engine::Plugin

PROTOTYPES: DISABLE

BOOT:
{
    if (!rep_booted++) {
        PERL_HASH(rep_hash, __PACKAGE__, __PACKAGE_LEN__);
    }

    rep_setup();
}

#if REP_THREADSAFE

void
CLONE(...)
PREINIT:
    ptable *t;
    int    *level;
CODE:
    {
	my_cxt_t ud;
	dMY_CXT;
	ud.tbl   = t = ptable_new();
	ud.owner = MY_CXT.owner;
	ptable_walk(MY_CXT.tbl, rep_ptable_clone, &ud);
    }
    {
	MY_CXT_CLONE;
	MY_CXT.tbl   = t;
	MY_CXT.owner = aTHX;
    }

#endif

void
pattern(re::engine::Plugin self, ...)
PPCODE:
    XPUSHs(self->pattern);

void
str(re::engine::Plugin self, ...)
PPCODE:
    XPUSHs(self->str);

char*
mod(re::engine::Plugin self, ...)
PPCODE:
    /* /i */
    if (self->rx->intflags & PMf_FOLD) {
      XPUSHs(sv_2mortal(newSVpvs("i")));
      XPUSHs(&PL_sv_yes);
    }

    /* /m */
    if (self->rx->intflags & PMf_MULTILINE) {
      XPUSHs(sv_2mortal(newSVpvs("m")));
      XPUSHs(&PL_sv_yes);
    }

    /* /s */
    if (self->rx->intflags & PMf_SINGLELINE) {
      XPUSHs(sv_2mortal(newSVpvs("s")));
      XPUSHs(&PL_sv_yes);
    }

    /* /x */
    if (self->rx->intflags & PMf_EXTENDED) {
      XPUSHs(sv_2mortal(newSVpvs("x")));
      XPUSHs(&PL_sv_yes);
    }

    /* /p */
    if (self->rx->intflags & RXf_PMf_KEEPCOPY) {
      XPUSHs(sv_2mortal(newSVpvs("p")));
      XPUSHs(&PL_sv_yes);
    }

void
stash(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->stash = ST(1);
        SvREFCNT_inc(self->stash);
        XSRETURN_EMPTY;
    } else {
        XPUSHs(self->stash);
    }

void
minlen(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->rx->minlen = (I32)SvIV(ST(1));
        XSRETURN_EMPTY;
    } else {
        if (self->rx->minlen) {
            XPUSHs(sv_2mortal(newSViv(self->rx->minlen)));
        } else {
            XPUSHs(sv_2mortal(&PL_sv_undef));
        }
    }

void
gofs(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->rx->gofs = (U32)SvIV(ST(1));
        XSRETURN_EMPTY;
    } else {
        if (self->rx->gofs) {
            XPUSHs(sv_2mortal(newSVuv(self->rx->gofs)));
        } else {
            XPUSHs(sv_2mortal(&PL_sv_undef));
        }
    }

void
nparens(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->rx->nparens = (U32)SvIV(ST(1));
        XSRETURN_EMPTY;
    } else {
        if (self->rx->nparens) {
            XPUSHs(sv_2mortal(newSVuv(self->rx->nparens)));
        } else {
            XPUSHs(sv_2mortal(&PL_sv_undef));
        }
    }

void
_num_capture_buff_FETCH(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_num_capture_buff_FETCH = ST(1);
        SvREFCNT_inc(self->cb_num_capture_buff_FETCH);
    }

void
_num_capture_buff_STORE(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_num_capture_buff_STORE = ST(1);
        SvREFCNT_inc(self->cb_num_capture_buff_STORE);
    }

void
_num_capture_buff_LENGTH(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_num_capture_buff_LENGTH = ST(1);
        SvREFCNT_inc(self->cb_num_capture_buff_LENGTH);
    }

SV *
_tag(SV *comp, SV *exec)
CODE:
    RETVAL = rep_tag(comp, exec);
OUTPUT:
    RETVAL

void
ENGINE()
PPCODE:
    XPUSHs(sv_2mortal(newSViv(PTR2IV(&engine_plugin))));
