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
Plugin_comp(pTHX_ const SV * const pattern, const U32 flags)
{
    dSP;
    REGEXP * rx;
    re__engine__Plugin re;
    I32 count;
    I32 buffers;

    /* exp/xend version of the pattern & length */
    STRLEN plen;
    char*  exp = SvPV((SV*)pattern, plen);
    char* xend = exp + plen;

    /* The REGEXP structure to return to perl */
    Newxz(rx, 1, REGEXP);

    /* Our blessed object */
    SV *obj = newSV(0);
    SvREFCNT_inc(obj);
    Newxz(re, 1, struct replug);
    sv_setref_pv(obj, "re::engine::Plugin", (void*)re);

    re->rx = rx;                   /* Make the rx accessible from self->rx */
    rx->refcnt = 1;                /* Refcount so we won' be destroyed */
    rx->intflags = flags;          /* Flags for internal use */
    rx->extflags = flags;          /* Flags for perl to use */
    rx->engine = RE_ENGINE_PLUGIN; /* Compile to use this engine */

    /* Precompiled regexp for pp_regcomp to use */
    rx->prelen = plen;
    rx->precomp = savepvn(exp, rx->prelen);

    /* Set up qr// stringification to be equivalent to the supplied
     * pattern, this should be done via overload eventually.
     */
    rx->wraplen = rx->prelen;
    Newx(rx->wrapped, rx->wraplen, char);
    Copy(rx->precomp, rx->wrapped, rx->wraplen, char);

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

    Newxz(rx->offs, buffers, regexp_paren_pair);

    return rx;
}

I32
Plugin_exec(pTHX_ REGEXP * const rx, char *stringarg, char *strend,
            char *strbeg, I32 minend, SV *sv, void *data, U32 flags)
{
    dSP;
    I32 matched;
    SV * callback = get_H_callback("exec");
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
Plugin_intuit(pTHX_ REGEXP * const rx, SV *sv, char *strpos,
                     char *strend, U32 flags, re_scream_pos_data *data)
{
    PERL_UNUSED_ARG(rx);
    PERL_UNUSED_ARG(sv);
    PERL_UNUSED_ARG(strpos);
    PERL_UNUSED_ARG(strend);
    PERL_UNUSED_ARG(flags);
    PERL_UNUSED_ARG(data);
    return NULL;
}

SV *
Plugin_checkstr(pTHX_ REGEXP * const rx)
{
    PERL_UNUSED_ARG(rx);
    return NULL;
}

void
Plugin_free(pTHX_ REGEXP * const rx)
{
    PERL_UNUSED_ARG(rx);
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
Plugin_dupe(pTHX_ const REGEXP * rx, CLONE_PARAMS *param)
{
    Perl_croak("dupe not supported yet");
    return rx->pprivate;
}

void
Plugin_numbered_buff_FETCH(pTHX_ REGEXP * const rx, const I32 paren,
                           SV * const sv)
{
    dSP;
    I32 items;
    SV * callback;
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
Plugin_numbered_buff_STORE(pTHX_ REGEXP * const rx, const I32 paren,
                           SV const * const value)
{
    dSP;
    I32 items;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_num_capture_buff_STORE;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(paren)));
        XPUSHs(SvREFCNT_inc(value));
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

I32
Plugin_numbered_buff_LENGTH(pTHX_ REGEXP * const rx, const SV * const sv,
                              const I32 paren)
{
    dSP;
    I32 items;
    SV * callback;
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
Plugin_named_buff_FETCH(pTHX_ REGEXP * const rx, SV * const key, U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_FETCH;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(SvREFCNT_inc(key));
        XPUSHs(sv_2mortal(newSViv(flags & 1 ? 1 : 0)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        SV* ret = POPs;
        SvREFCNT_inc(ret);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return ret;
    } else {
        return NULL;
    }
}

void
Plugin_named_buff_STORE(pTHX_ REGEXP * const rx, SV * const key,
                        SV * const value, const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_STORE;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(SvREFCNT_inc(key));
        XPUSHs(SvREFCNT_inc(value));
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

void
Plugin_named_buff_DELETE(pTHX_ REGEXP * const rx, SV * const key, const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_DELETE;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(SvREFCNT_inc(key));
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

void
Plugin_named_buff_CLEAR(pTHX_ REGEXP * const rx, const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_CLEAR;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_DISCARD);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

bool
Plugin_named_buff_EXISTS(pTHX_ REGEXP * const rx, SV * const key,
                         const U32 flags)
{
    dSP;
    SV * callback;
    bool truthiness = FALSE;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_EXISTS;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(SvREFCNT_inc(key));
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        SV * ret = POPs;
        truthiness = SvTRUE(ret);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }

    return truthiness;
}

SV*
Plugin_named_buff_FIRSTKEY(pTHX_ REGEXP * const rx, const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_FIRSTKEY;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        SV * ret = POPs;
        SvREFCNT_inc(ret);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return ret;
    } else {
        return NULL;
    }
}

SV*
Plugin_named_buff_NEXTKEY(pTHX_ REGEXP * const rx, SV * const lastkey,
                          const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_NEXTKEY;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(SvREFCNT_inc(lastkey));
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        SV * ret = POPs;
        SvREFCNT_inc(ret);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return ret;
    } else {
        return NULL;
    }
}

SV*
Plugin_named_buff_SCALAR(pTHX_ REGEXP * const rx, const U32 flags)
{
    dSP;
    SV * callback;
    GET_SELF_FROM_PPRIVATE(rx->pprivate);

    callback = self->cb_named_capture_buff_SCALAR;

    if (callback) {
        ENTER;
        SAVETMPS;
   
        PUSHMARK(SP);
        XPUSHs(rx->pprivate);
        XPUSHs(sv_2mortal(newSViv(flags)));
        PUTBACK;

        call_sv(callback, G_SCALAR);

        SPAGAIN;

        SV * ret = POPs;
        SvREFCNT_inc(ret);

        PUTBACK;
        FREETMPS;
        LEAVE;

        return ret;
    } else {
        return NULL;
    }
}

SV*
Plugin_package(pTHX_ REGEXP * const rx)
{
    PERL_UNUSED_ARG(rx);
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

void
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
_named_capture_buff_FETCH(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_FETCH = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_FETCH);
    }

void
_named_capture_buff_STORE(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_STORE = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_STORE);
    }

void
_named_capture_buff_DELETE(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_DELETE = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_DELETE);
    }

void
_named_capture_buff_CLEAR(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_CLEAR = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_CLEAR);
    }

void
_named_capture_buff_EXISTS(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_EXISTS = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_EXISTS);
    }

void
_named_capture_buff_FIRSTKEY(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_FIRSTKEY = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_FIRSTKEY);
    }

void
_named_capture_buff_NEXTKEY(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_NEXTKEY = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_NEXTKEY);
    }

void
_named_capture_buff_SCALAR(re::engine::Plugin self, ...)
PPCODE:
    if (items > 1) {
        self->cb_named_capture_buff_SCALAR = ST(1);
        SvREFCNT_inc(self->cb_named_capture_buff_SCALAR);
    }

void
ENGINE()
PPCODE:
    XPUSHs(sv_2mortal(newSViv(PTR2IV(&engine_plugin))));
