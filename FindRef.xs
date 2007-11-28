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

#define res_pair(text)					\
  {							\
    AV *av = newAV ();					\
    av_push (av, newSVpv (text, 0));			\
    av_push (av, newRV_inc (sv));			\
    av_push (about, newRV_noinc ((SV *)av));		\
  }

#define res_gv(sigil)					\
  {							\
    AV *av = newAV ();					\
    av_push (av, newSVpv (form ("in the global %c%s::%.*s", sigil, \
                                HvNAME (GvSTASH (sv)), \
                                GvNAMELEN (sv), GvNAME (sv) ? GvNAME (sv) : "<anonymous>"), \
                          0));				\
    av_push (about, newRV_noinc ((SV *)av));		\
  }

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
        int rmagical, i;
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

                switch (SvTYPE (sv))
                  {
                    case SVt_RV:
                      if (sv != target && SvRV (sv) == targ)
                        res_pair ("referenced by");
                      break;

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
                        if (depth)
                          {
                            AV *padlist = CvPADLIST (sv);
                            while (depth)
                              {
                                AV *pad = (AV *)AvARRAY (padlist)[depth];
                                av_push (excl, newSVuv (PTR2UV (pad))); /* exclude pads from being found */
                                for (i = AvFILLp (pad); i--; )
                                  if (AvARRAY (pad)[i] == targ)
                                    res_pair (form ("in the lexical '%s' in", SvPVX (AvARRAY (AvARRAY (padlist)[0])[i])));

                                --depth;
                              }
                          }
                      }
                      break;

                    case SVt_PVGV:
                      if (GvGP (sv))
                        {
                          if (GvSV (sv) == targ)
                            res_gv ('$');
                          if (GvAV (sv) == (AV *)targ)
                            res_gv ('@');
                          if (GvHV (sv) == (HV *)targ)
                            res_gv ('%');
                          if (GvCV (sv) == (CV *)targ)
                            res_gv ('&');
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

