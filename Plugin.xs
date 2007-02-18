#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define SAVEPVN(p,n)	((p) ? savepvn(p,n) : NULL)

START_EXTERN_C

EXTERN_C const regexp_engine engine_plugin;

END_EXTERN_C

/*
 * Our struct which gets initiated and used as our object
 * ($re). Since we can't count on the regexp structure provided by
 * perl to be alive between comp/exec etc. we pull stuff from it and
 * save it in our own structure.
 *
 * Besides, creating Perl accessors which directly muck with perl's
 * own regexp structures in different phases of regex execution would
 * be a little too evil.
 */
typedef struct replug {
    SV * pattern;
    char flags[sizeof("ecgimsxp")];

    I32 minlen;
    U32 gofs;

    SV * stash;

    U32 nparens;
    AV * captures; /* Array of SV* that'll become $1, $2, ... */
} *re__engine__Plugin;

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

    call_pv("re::engine::Plugin::get_callback", G_SCALAR);

    SPAGAIN;

    callback = POPs;
    SvREFCNT_inc(callback);

    if (!SvROK(callback)) { callback = NULL; }// croak("ret value not a ref"); }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return callback;
}

/* just learn to use gdb you lazy bum! */
#if 0
void
dump_r_info(const char* id, regexp *r)
{
    warn("%s:", id);
    warn("\textflags = %d", r->extflags);
    warn("\tminlen = %d", r->minlen);
    warn("\tminlenren = %d", r->minlenret);
    warn("\tgofs = %d", r->gofs);
    warn("\tnparens = %d", r->nparens);
    warn("\tpprivate = %p", r->pprivate);
    warn("\tsubbeg = %s", r->subbeg);
    warn("\tsublen = %d", r->sublen);
    warn("\tprecomp = %s", r->precomp);
    warn("\tprelen = %d", r->prelen);
    warn("\twrapped = %s", r->wrapped);
    warn("\twraplen = %d", r->wraplen);
    warn("\tseen_evals = %d", r->seen_evals);
    warn("\trefcnt = %d", r->refcnt);
    
}
#endif

regexp *
Plugin_comp(pTHX_ char *exp, char *xend, PMOP *pm)
{
    dSP;
    register regexp *r;
    int count;

    /*
     * Allocate a new regexp struct, we must only write to the intflags,
     * engine and private members and the others must be populated,
     * internals expect the regex to have certain values least our code
     * blow up
     */

    Newxz(r,1,regexp);

    /* Set up the regex to be handled by this plugin */
    r->engine = &engine_plugin;

    /* Store the initial flags */
    r->intflags = pm->op_pmflags;
    r->pprivate = NULL; /* this is set to our object below */

    /*
     * Populate the regexp members for the engine
     */

    /* Ref count of the pattern */
    r->refcnt = 1;

    /* Preserve a copy of the original pattern */
    r->prelen = xend - exp;
    r->precomp = SAVEPVN(exp, r->prelen);

    /* these may be changed by accessors */
    r->minlen = 0;
    r->minlenret = 0;
    r->gofs = 0;
    r->nparens = 0;

    /* Store the flags as perl expects them */
    r->extflags = pm->op_pmflags & RXf_PMf_COMPILETIME;

    /*
     * Construct a new B<re::engine::Plugin> object that'll carry around
     * our data inside C<< r->pprivate >>. The object is a blessed void*
     * that points to our replug struct which holds any state we want to
     * keep.
     */
    re__engine__Plugin re;
    Newz(0, re, 1, struct replug);
    
    SV *obj = newSV(0);
    SvREFCNT_inc(obj);

    /* Bless into this package; TODO: make it subclassable */
    const char * pkg = "re::engine::Plugin";
    /* bless it */
    sv_setref_pv(obj, pkg, (void*)re);

    /* Store our private object */
    r->pprivate = obj;

    re->pattern = newSVpvn(SAVEPVN(exp, xend - exp), xend - exp);
    SvREFCNT_inc(re->pattern);

    /* Concat [ec]gimosxp (egimosxp & cgimosxp into) the flags string as
     * appropriate
     */
    if (r->intflags & PMf_EVAL)       { strcat(re->flags, "e"); }
    if (r->intflags & PMf_CONTINUE)   { strcat(re->flags, "c"); }
    if (r->intflags & PMf_GLOBAL)     { strcat(re->flags, "g"); }
    if (r->intflags & PMf_FOLD)       { strcat(re->flags, "i"); }
    if (r->intflags & PMf_MULTILINE)  { strcat(re->flags, "m"); }
    if (r->intflags & PMf_ONCE)       { strcat(re->flags, "o"); }
    if (r->intflags & PMf_SINGLELINE) { strcat(re->flags, "s"); }
    if (r->intflags & PMf_EXTENDED)   { strcat(re->flags, "x"); }
    if (((r->extflags & RXf_PMf_KEEPCOPY) == RXf_PMf_KEEPCOPY)) {
        strcat(re->flags, "p"); 
    }

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
        XPUSHs(sv_2mortal(newSVpv(exp, xend - exp)));
    
        PUTBACK;

        call_sv(get_H_callback("comp"), G_DISCARD);

        FREETMPS;
        LEAVE;
    }

    /* If any of the comp-time accessors were called we'll have to
     * update the regexp struct with the new info.
     */
    if (re->minlen)  r->minlen  = re->minlen;
    if (re->gofs)    r->gofs    = re->gofs;
    if (re->gofs)    r->gofs    = re->gofs;
    if (re->nparens) r->nparens = re->nparens;

    int buffers = r->nparens;

    //r->nparens = (buffers - 1);
    Newxz(r->startp, buffers, I32);
    Newxz(r->endp, buffers, I32);

    /* return the regexp */
    return r;
}

I32
Plugin_exec(pTHX_ register regexp *r, char *stringarg, register char *strend,
                  char *strbeg, I32 minend, SV *sv, void *data, U32 flags)
{
    dSP;
    I32 rc;
    int *ovector;
    I32 i;
    int count;
    int ret;

    /*Newx(ovector,r->nparens,int);*/

    SV* callback = get_H_callback("exec");

    ENTER;    
    SAVETMPS;
   
    PUSHMARK(SP);

    XPUSHs(r->pprivate);
    XPUSHs(sv);

    PUTBACK;

    count = call_sv(callback, G_ARRAY);
 
    SPAGAIN;

    SV * SvRet = POPs;

    if (SvTRUE(SvRet)) {
        /* Match vars */

        /*
        r->sublen = strend-strbeg;
        r->subbeg = savepvn(strbeg,r->sublen);
        r->startp[1] = 0;
        r->endp[1] = 5;
        */

        ret = 1;
    } else {
        ret = 0;
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    return ret;
}

char *
Plugin_intuit(pTHX_ regexp *prog, SV *sv, char *strpos,
                     char *strend, U32 flags, re_scream_pos_data *data)
{
    return NULL;
}

SV *
Plugin_checkstr(pTHX_ regexp *prog)
{
    return NULL;
}

void
Plugin_free(pTHX_ struct regexp *r)
{
    /*sv_2mortal(r->pprivate);*/
    /*PerlMemShared_free(r->pprivate);*/
}

void *
Plugin_dupe(pTHX_ const regexp *r, CLONE_PARAMS *param)
{
    return r->pprivate;
}

SV*
Plugin_numbered_buff_get(pTHX_ const REGEXP * const rx, I32 paren, SV* usesv)
{
    return NULL;
}

SV*
Plugin_named_buff_get(pTHX_ const REGEXP * const rx, SV* namesv, U32 flags)
{
    return NULL;
}

/*
 * The function pointers we're telling the regex engine to use
 */
const regexp_engine engine_plugin = {
        Plugin_comp,
        Plugin_exec,
        Plugin_intuit,
        Plugin_checkstr,
        Plugin_free,
        Plugin_numbered_buff_get,
        Plugin_named_buff_get,
#if defined(USE_ITHREADS)        
        Plugin_dupe,
#endif
};

MODULE = re::engine::Plugin	PACKAGE = re::engine::Plugin

SV *
pattern(re::engine::Plugin self, ...)
CODE:
    SvREFCNT_inc(self->pattern);
    RETVAL = self->pattern;
OUTPUT:
    RETVAL

char*
flags(re::engine::Plugin self, ...)
CODE:
    RETVAL = self->flags;
OUTPUT:
    RETVAL

SV *
stash(re::engine::Plugin self, ...)
PREINIT:
    SV * stash;
CODE:
    if (items > 1) {
        self->stash = sv_mortalcopy(ST(1));
        SvREFCNT_inc(self->stash);
    }
    SvREFCNT_inc(self->stash);
    RETVAL = self->stash;
OUTPUT:
    RETVAL

SV *
minlen(re::engine::Plugin self, ...)
CODE:
    if (items > 1) {
        self->minlen = (I32)SvIV(ST(1));
    }

    RETVAL = self->minlen ? newSViv(self->minlen) : &PL_sv_undef;
OUTPUT:
    RETVAL

SV *
gofs(re::engine::Plugin self, ...)
CODE:
    if (items > 1) {
        self->gofs = (U32)SvIV(ST(1));
    }
    RETVAL = self->gofs ? newSVuv(self->gofs) : &PL_sv_undef;
OUTPUT:
    RETVAL

SV *
nparens(re::engine::Plugin self, ...)
CODE:
    if (items > 1) {
        self->nparens = (U32)SvIV(ST(1));
    }
    RETVAL = self->gofs ? newSVuv(self->gofs) : &PL_sv_undef;
OUTPUT:
    RETVAL

void
captures(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->minlen = (I32)SvIV(ST(1));
    }
    XPUSHs(sv_2mortal(newSViv(5)));
    XPUSHs(sv_2mortal(newSViv(10)));

void
get_engine_plugin()
PPCODE:
    XPUSHs(sv_2mortal(newSViv(PTR2IV(&engine_plugin))));
