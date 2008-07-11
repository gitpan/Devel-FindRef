#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define PERL_VERSION_ATLEAST(a,b,c)                             \
  (PERL_REVISION > (a)                                          \
   || (PERL_REVISION == (a)                                     \
       && (PERL_VERSION > (b)                                   \
           || (PERL_VERSION == (b) && PERLSUBVERSION >= (c)))))

#if !PERL_VERSION_ATLEAST (5,8,9)
# define SVt_LAST 16
#endif

#if !PERL_VERSION_ATLEAST (5,10,0)
# define SvPAD_OUR(dummy) 0
#endif

#define res_pair(text)						\
  do {								\
    AV *av = newAV ();						\
    av_push (av, newSVpv (text, 0));				\
    if (rmagical) SvRMAGICAL_on (sv);				\
    av_push (av, sv_rvweaken (newRV_inc (sv)));			\
    if (rmagical) SvRMAGICAL_off (sv);				\
    av_push (about, newRV_noinc ((SV *)av));			\
  } while (0)

#define res_text(text)						\
  do {								\
    AV *av = newAV ();						\
    av_push (av, newSVpv (text, 0));				\
    av_push (about, newRV_noinc ((SV *)av));			\
  } while (0)

#define res_gv(sigil)						\
  res_text (form ("in the global %c%s::%.*s", sigil,		\
                  HvNAME (GvSTASH (sv)),			\
                  GvNAMELEN (sv),				\
                  GvNAME (sv) ? GvNAME (sv) : "<anonymous>"))

MODULE = Devel::FindRef		PACKAGE = Devel::FindRef		

PROTOTYPES: ENABLE

SV *
ptr2ref (IV ptr)
	CODE:
        RETVAL = newRV_inc (INT2PTR (SV *, ptr));
	OUTPUT:
        RETVAL

void
find_ (SV *target)
	PPCODE:
{
  	SV *arena, *targ;
        U32 rmagical;
        int i;
        AV *about = newAV ();
        AV *excl  = newAV ();

  	if (!SvROK (target))
          croak ("find expects a reference to a perl value");

        targ = SvRV (target);

	for (arena = PL_sv_arenaroot; arena; arena = SvANY (arena))
          {
            UV idx = SvREFCNT (arena);

            /* Remember that the zeroth slot is used as the pointer onwards, so don't
               include it. */
            while (--idx > 0)
              {
                SV *sv = &arena [idx];

                if (SvTYPE (sv) >= SVt_LAST)
                  continue;

                /* temporarily disable RMAGICAL, it can easily interfere with us */
                if ((rmagical = SvRMAGICAL (sv)))
                  SvRMAGICAL_off (sv);

                if (SvTYPE (sv) >= SVt_PVMG)
                  {
                    if (SvTYPE (sv) == SVt_PVMG && SvPAD_OUR (sv))
                      {
                        /* I have no clue what this is */
                        /* maybe some placeholder for our variables for eval? */
                        /* it doesn't seem to reference anything, so we should be able to ignore it */
                      }
                    else
                      {
                        MAGIC *mg = SvMAGIC (sv);

                        while (mg)
                          {
                            if (mg->mg_obj == targ)
                              res_pair (form ("referenced (in mg_obj) by '%c' type magic attached to", mg->mg_type));

                            if ((SV *)mg->mg_ptr == targ && mg->mg_flags & MGf_REFCOUNTED)
                              res_pair (form ("referenced (in mg_ptr) by '%c' type magic attached to", mg->mg_type));

                            mg = mg->mg_moremagic;
                          }
                      }
                  }

                if (SvROK (sv))
                  {
                    if (sv != target && SvRV (sv) == targ && !SvWEAKREF (sv))
                      res_pair ("referenced by");
                  }
                else
                  switch (SvTYPE (sv))
                    {
                      case SVt_PVAV:
                        if (AvREAL (sv))
                          for (i = AvFILLp (sv) + 1; i--; )
                            if (AvARRAY (sv)[i] == targ)
                              res_pair (form ("in array element %d of", i));

                        break;

                      case SVt_PVHV:
                        if (hv_iterinit ((HV *)sv))
                          {
                            HE *he;

                            while ((he = hv_iternext ((HV *)sv)))
                              if (HeVAL (he) == targ)
                                res_pair (form ("in the member '%.*s' of", HeKLEN (he), HeKEY (he)));
                          }

                        break;

                      case SVt_PVCV:
                        {
                          int depth = CvDEPTH (sv);

                          /* Anonymous subs have a padlist but zero depth */
                          if (CvANON (sv) && !depth && CvPADLIST (sv))
                            depth = 1;

                          if (depth)
                            {
                              AV *padlist = CvPADLIST (sv);

                              while (depth)
                                {
                                  AV *pad = (AV *)AvARRAY (padlist)[depth];

                                  av_push (excl, newSVuv (PTR2UV (pad))); /* exclude pads themselves from being found */

                                  for (i = AvFILLp (pad) + 1; i--; )
                                    if (AvARRAY (pad)[i] == targ)
                                      {
                                        /* Values from constant functions are stored in the pad without any name */
                                        SV *name_sv = AvARRAY (AvARRAY (padlist)[0])[i];

                                        if (name_sv && SvPOK (name_sv))
                                          res_pair (form ("in the lexical '%s' in", SvPVX (name_sv)));
                                        else
                                          res_pair ("in an unnamed lexical in");
                                      }

                                  --depth;
                                }
                            }

                          if (CvCONST (sv) && (SV*)CvXSUBANY (sv).any_ptr == targ)
                            res_pair ("the constant value of");

                          if (!CvWEAKOUTSIDE (sv) && (SV*)CvOUTSIDE (sv) == targ)
                            res_pair ("the containing scope for");

                          if (sv == targ && CvANON (sv))
                            if (CvSTART (sv)
                                && CvSTART (sv)->op_type == OP_NEXTSTATE
                                && CopLINE ((COP *)CvSTART (sv)))
                              res_text (form ("the closure created at %s:%d",
                                              CopFILE ((COP *)CvSTART (sv)) ? CopFILE ((COP *)CvSTART (sv)) : "<unknown>",
                                              CopLINE ((COP *)CvSTART (sv))));
                            else
                              res_text (form ("the closure created somewhere in file %s (PLEASE REPORT!)",
                                              CvFILE (sv) ? CvFILE (sv) : "<unknown>"));
                        }

                        break;

                      case SVt_PVGV:
                        if (GvGP (sv))
                          {
                            if (GvSV (sv) == (SV *)targ) res_gv ('$');
                            if (GvAV (sv) == (AV *)targ) res_gv ('@');
                            if (GvHV (sv) == (HV *)targ) res_gv ('%');
                            if (GvCV (sv) == (CV *)targ) res_gv ('&');
                          }

                        break;
                    }

                if (rmagical)
                  SvRMAGICAL_on (sv);
              }
          }

        EXTEND (SP, 2);
        PUSHs (sv_2mortal (newRV_noinc ((SV *)about)));
        PUSHs (sv_2mortal (newRV_noinc ((SV *)excl)));
}

