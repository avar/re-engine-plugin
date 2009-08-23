#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "Plugin.h"

SV*
get_H_callback(const char* key)
{
    dVAR;
    dSP;

    SV * callback;

    ENTER;
    SAVETMPS;
   
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(key, 0)));
    PUTBACK;

    call_pv("re::engine::Plugin::_get_callback", G_SCALAR);

    SPAGAIN;

    callback = POPs;
    SvREFCNT_inc(callback); /* refcount++ or FREETMPS below will collect us */

    /* If we don't get a valid CODE value return a NULL callback, in
     * that case the hooks won't call back into Perl space */
    if (!SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV) {
        callback = NULL;
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return callback;
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
    re__engine__Plugin re;
    I32 buffers;

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
    SV * callback = get_H_callback("comp");

    if (callback) {
        ENTER;    
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(obj);
        PUTBACK;

        call_sv(callback, G_DISCARD);

        FREETMPS;
        LEAVE;
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
    SV * callback = get_H_callback("exec");
    struct regexp *rx = rxREGEXP(RX);
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    if (callback) {
        /* Store the current str for ->str */
        self->str = (SV*)sv;
        SvREFCNT_inc(self->str);

        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv);
        PUTBACK;

        call_sv(callback, G_SCALAR);
 
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

MODULE = re::engine::Plugin	PACKAGE = re::engine::Plugin
PROTOTYPES: DISABLE

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

void
ENGINE()
PPCODE:
    XPUSHs(sv_2mortal(newSViv(PTR2IV(&engine_plugin))));
