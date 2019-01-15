MODULE mo_salsa_driver
  USE classSection, ONLY : Section
  USE util, ONLY : getMassIndex !!! IS it good to import this here??? The function is anyway handy here too.
  USE mo_salsa_types, ONLY : aero, cloud, precp, ice, allSALSA
  USE mo_submctl
  IMPLICIT NONE

   !---------------------------------------------------------------
   !
   ! MO_SALSA_DRIVER:
   ! Contains the primary SALSA input/output variables as well as
   ! Subroutines used to call the main SALSA routine.
   !
   ! Juha Tonttila, FMI, 2014
   !
   !---------------------------------------------------------------

   ! JT: Variables from SALSA
   ! --------------------------------------------
   ! grid points for SALSA
   INTEGER, PARAMETER :: kproma = 1
   INTEGER, PARAMETER :: kbdim = 1
   INTEGER, PARAMETER :: klev = 1
   INTEGER, PARAMETER :: krow = 1

   REAL, PARAMETER    :: init_rh(kbdim,klev) = 0.3

   ! -- Local gas compound tracers [# m-3]
   REAL :: zgso4(kbdim,klev),   &
           zghno3(kbdim,klev),  &
           zgnh3(kbdim,klev),   &
           zgocnv(kbdim,klev),  &
           zgocsv(kbdim,klev)

 ! --------------------------------------------

CONTAINS

   !
   !----------------------------------------------------
   ! RUN_SALSA
   ! Performs necessary unit and dimension conversion between
   ! the host model and SALSA module, and calls the main SALSA
   ! routine
   !
   ! Partially adobted form the original SALSA boxmodel version.
   !
   ! Now takes masses in as kg/kg from LES!! Converted to m3/m3 for SALSA
   !
   ! 05/2016 Juha: This routine is still pretty much in its original shape.
   !               It's dumb as a mule and twice as ugly, so implementation of
   !               an improved solution is necessary sooner or later.
   !
   ! Juha Tonttila, FMI, 2014
   ! Jaakko Ahola, FMI, 2016
   !
   SUBROUTINE run_SALSA(pnx, pny, pnz, ns, press, tk, rv, rt, rs, rsi, wp, pdn,   &
                        pa_naerop,  pa_naerot,  pa_maerop,  pa_maerot,   &
                        pa_ncloudp, pa_ncloudt, pa_mcloudp, pa_mcloudt,  &
                        pa_nprecpp, pa_nprecpt, pa_mprecpp, pa_mprecpt,  &
                        pa_nicep,   pa_nicet,   pa_micep,   pa_micet,    &
                        pa_nactd,   pa_vactd,   pa_gaerop,  pa_gaerot,   &
                        tstep, time, level, initialize)

      USE mo_salsa, ONLY : salsa
      USE mo_salsa_properties, ONLY  : equilibration
      IMPLICIT NONE

      INTEGER, INTENT(in) :: pnx,pny,pnz,ns                       ! dimensions: x,y,z,number of chemical species
      REAL, INTENT(in)    :: tstep                                ! Model timestep length
      REAL, INTENT(in)    :: time
      
      LOGICAL, INTENT(in) :: initialize                      

      REAL, INTENT(in)    :: press(pnz,pnx,pny), &            ! Pressure (Pa)
                             tk(pnz,pnx,pny),    &            ! Temperature (K)
                             rv(pnz,pnx,pny),    &            ! Water vapor mixing ratio
                             rs(pnz,pnx,pny),    &            ! Water vapour saturation mixing ratio
                             rsi(pnz,pnx,pny),   &            ! water vapour sat mix rat over ice
                             wp(pnz,pnx,pny)                  ! Vertical velocity (m s-1)

      REAL, INTENT(in)    :: pdn(pnz,pnx,pny)             ! Air density (for normalizing concentrations)

      REAL, INTENT(in)    :: pa_naerop(pnz,pnx,pny,nbins),        & ! aerosol number concentration (# kg-1)
                             pa_maerop(pnz,pnx,pny,ns*nbins),     & ! aerosol mass concentration (kg kg-1)
                             pa_ncloudp(pnz,pnx,pny,ncld),        & ! Cloud droplet number concentration (# kg-1)
                             pa_mcloudp(pnz,pnx,pny,ns*ncld),     & ! Cloud droplet mass concentration (kg kg-1)
                             pa_nprecpp(pnz,pnx,pny,nprc),        & ! Rain drop number concentration (# kg-1)
                             pa_mprecpp(pnz,pnx,pny,ns*nprc),     & ! Rain drop mass concentration (kg kg-1)
                             pa_nicep(pnz,pnx,pny,nice),          & ! ice number concentration (# kg-1)
                             pa_micep(pnz,pnx,pny,(ns+1)*nice)      ! ice mass concentration (kg kg-1)

      REAL, INTENT(in)    :: pa_gaerop(pnz,pnx,pny,5)         ! Gaseous tracers [# kg]

      INTEGER, INTENT(in) :: level                         ! thermodynamical level

      REAL, INTENT(inout) :: pa_naerot(pnz,pnx,pny,nbins),      & ! Aerosol number tendency
                             pa_maerot(pnz,pnx,pny,ns*nbins),   & ! Aerosol mass tendency
                             pa_ncloudt(pnz,pnx,pny,ncld),      & ! Cloud droplet number tendency
                             pa_mcloudt(pnz,pnx,pny,ns*ncld),   & ! Cloud droplet mass tendency
                             pa_nprecpt(pnz,pnx,pny,nprc),      & ! Rain drop number tendency
                             pa_mprecpt(pnz,pnx,pny,ns*nprc),   &  ! Rain drop mass tendency
                             pa_nicet(pnz,pnx,pny,nice),        & ! Ice particle number tendency
                             pa_micet(pnz,pnx,pny,(ns+1)*nice)    ! Ice particle mass tendency

      REAL, INTENT(inout) :: pa_gaerot(pnz,pnx,pny,5)         ! Gaseous tracer tendency
      REAL, INTENT(inout) :: rt(pnz,pnx,pny)                  ! Water vapour tendency

      REAL, INTENT(out) :: pa_vactd(pnz,pnx,pny,ns*ncld) ! Volume concentrations of newly activated droplets for calculating the
                                                           ! actual tendency due to new droplet formation.
      REAL, INTENT(out) :: pa_nactd(pnz,pnx,pny,ncld)   ! Same for number concentration

      TYPE(Section) :: actd(kbdim,klev,ncld) ! Activated droplets - for interfacing with SALSA

      ! Helper arrays for calculating the rates of change
      TYPE(Section) :: aero_old(kbdim,klev,nbins), cloud_old(kbdim,klev,ncld),    &
                       precp_old(kbdim,klev,nprc), ice_old(kbdim,klev,nice)

      INTEGER :: jj,ii,kk,ss,str,end,str2,end2, nc, ndry, iwa, irim
      REAL :: in_p(kbdim,klev), in_t(kbdim,klev), in_rv(kbdim,klev), in_rs(kbdim,klev),&
              in_w(kbdim,klev), in_rsi(kbdim,klev)
      REAL :: rv_old(kbdim,klev)

      REAL :: mrim(nice), mprist(nice), mrim_old(nice), mprist_old(nice)


      ndry = spec%getNSpec(type="dry")
      iwa = spec%getIndex("H2O")    ! water/unrimed ice
      irim = spec%getIndex("rime")  ! rimed ice; returns 0 if level<5 and rime not used

      actd(:,:,:) = Section(2,nlim,dlcloud)
      ! these are used as containers for the "previous" values
      aero_old(:,:,:) = Section(1,nlim,dlaero)
      cloud_old(:,:,:) = Section(2,nlim,dlcloud)
      precp_old(:,:,:) = Section(3,prlim,dlprecp)
      IF (level == 5) THEN
         ice_old(:,:,:) = Section(4,prlim,dlice)
      END IF

      in_p(:,:) = 0.; in_t(:,:) = 0.; in_rs(:,:) = 0.; in_rsi(:,:) = 0.; in_w(:,:) = 0.
      in_rv(:,:) = 0.; rv_old(:,:) = 0.
      
      ! Set the SALSA runtime config 
      CALL set_salsa_runtime(time)

      ! Convert input concentrations for SALSA into #/m3 or m3/m3 instead of kg/kg (multiplied by pdn/divided by substance density)
      DO jj = 3, pny-2
         DO ii = 3, pnx-2
            DO kk = pnz-1, 2, -1

               ! Set inputs
               in_p(1,1) = press(kk,ii,jj)
               in_t(1,1) = tk(kk,ii,jj)
               in_rs(1,1) = rs(kk,ii,jj)
               in_rsi(1,1) = rsi(kk,ii,jj)
               in_w(1,1) = wp(kk,ii,jj)

               ! For initialization and spinup, limit the RH with the parameter rhlim (assign in namelist.salsa)
               IF ( lsfreeRH%state ) THEN
                  in_rv(1,1) = rv(kk,ii,jj)
               ELSE
                  in_rv(1,1) = MIN(rv(kk,ii,jj), rs(kk,ii,jj)*rhlim)
               END IF
               rv_old(1,1) = in_rv(1,1)
       
               ! Update volume concentrations
               ! ---------------------------------------------------------------------------------------------------
               ! Dry volumes
               DO nc = 1,ndry
                  str = getMassIndex(nbins,1,nc)
                  end = getMassIndex(nbins,nbins,nc)
                  aero(1,1,1:nbins)%volc(nc) =  pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(nc)

                  str = getMassIndex(ncld,1,nc)
                  end = getMassIndex(ncld,ncld,nc)
                  cloud(1,1,1:ncld)%volc(nc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(nc)

                  str = getMassIndex(nprc,1,nc)
                  end = getMassIndex(nprc,nprc,nc)
                  precp(1,1,1:nprc)%volc(nc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(nc)

                  IF (level == 5) THEN
                     str = getMassIndex(nice,1,nc) 
                     end = getMassIndex(nice,nice,nc)                     
                     ice(1,1,1:nice)%volc(nc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rhoice(nc)                    
                  ELSE
                     ice(1,1,1:nice)%volc(nc) = 0.
                  END IF
               END DO

               ! Water/ice
               str = getMassIndex(nbins,1,iwa)
               end = getMassIndex(nbins,nbins,iwa)
               aero(1,1,1:nbins)%volc(iwa) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(iwa)

               str = getMassIndex(ncld,1,iwa)
               end = getMassIndex(ncld,ncld,iwa)
               cloud(1,1,1:ncld)%volc(iwa) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(iwa)
            
               str = getMassIndex(nprc,1,iwa)
               end = getMassIndex(nprc,nprc,iwa)
               precp(1,1,1:nprc)%volc(iwa) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/spec%rholiq(iwa)

               IF (level == 5) THEN
                  ! Ice and rimed ice
                  str = getMassIndex(nice,1,iwa)    ! Pristine ice
                  end = getMassIndex(nice,nice,iwa)
                  str2 = getMassIndex(nice,1,irim) ! Rimed ice
                  end2 = getMassIndex(nice,nice,irim)

                  mrim = 0.; mprist = 0.
                  mrim(1:nice) = pa_micep(kk,ii,jj,str2:end2)
                  mprist(1:nice) = pa_micep(kk,ii,jj,str:end)

                  ice(1,1,1:nice)%volc(iwa) = pdn(kk,ii,jj) * ( (mprist/spec%rhoic) ) 
                  ice(1,1,1:nice)%volc(irim) = pdn(kk,ii,jj) * (mrim/spec%rhori)

               ELSE
                  ice(1,1,1:nice)%volc(iwa) = 0.
                  ice(1,1,1:nice)%volc(irim) = 0.
               END IF

               ! -------------------------------
               
               ! Update number concentrations and particle sizes
               ! ----------------------------------------------------------------------------
               aero(1,1,1:nbins)%numc = pa_naerop(kk,ii,jj,1:nbins)*pdn(kk,ii,jj)
               cloud(1,1,1:ncld)%numc = pa_ncloudp(kk,ii,jj,1:ncld)*pdn(kk,ii,jj)
               precp(1,1,1:nprc)%numc = pa_nprecpp(kk,ii,jj,1:nprc)*pdn(kk,ii,jj)
               IF (level > 4) THEN
                  ice(1,1,1:nice)%numc = pa_nicep(kk,ii,jj,1:nice)*pdn(kk,ii,jj)
               ELSE
                  ice(1,1,1:nice)%numc = 0.
               END IF

               DO ss = 1,ntotal
                  CALL allSALSA(1,1,ss)%updateDiameter(.TRUE.,type="all")
                  CALL allSALSA(1,1,ss)%updateRhomean()

                  IF (allSALSA(1,1,ss)%numc > allSALSA(1,1,ss)%nlim) THEN
                     allSALSA(1,1,ss)%core = SUM(allSALSA(1,1,ss)%volc(1:ndry))/allSALSA(1,1,ss)%numc
                  ELSE
                     allSALSA(1,1,ss)%core = pi6*(allSALSA(1,1,ss)%dmid)**3
                  END IF 
               END DO
               ! --------------------------------
               
               ! Take a copy of current concentrations to convert to tendencies after SALSA call
               aero_old = aero; cloud_old = cloud; precp_old = precp
               IF (level == 5) THEN
                  ice_old = ice
               END IF
        
               ! If this is an initialization call, calculate the equilibrium particle
               If (initialize) CALL equilibration(kproma,kbdim,klev,   &
                                                  init_rh,in_t,.TRUE.)

               ! Convert to #/m3
               zgso4(1,1) = pa_gaerop(kk,ii,jj,1)*pdn(kk,ii,jj)
               zghno3(1,1) = pa_gaerop(kk,ii,jj,2)*pdn(kk,ii,jj)
               zgnh3(1,1) = pa_gaerop(kk,ii,jj,3)*pdn(kk,ii,jj)
               zgocnv(1,1) = pa_gaerop(kk,ii,jj,4)*pdn(kk,ii,jj)
               zgocsv(1,1) = pa_gaerop(kk,ii,jj,5)*pdn(kk,ii,jj)

               ! ***************************************!
               !                Run SALSA               !
               ! ***************************************!
               CALL salsa(kproma, kbdim,  klev,   krow,     &
                          in_p,   in_rv,  in_rs,  in_rsi,   &
                          in_t,   tstep,  zgso4,  zgocnv,   &
                          zgocsv, zghno3, zgnh3,  actd,     &
                          in_w,   level                     )

               ! Make sure the mean densities (mainly for ice) are properly updated
               DO ss = 1,ntotal
                  CALL allSALSA(1,1,ss)%updateRhomean()
               END DO

               ! Calculate tendencies (convert back to #/kg or kg/kg)
               pa_naerot(kk,ii,jj,1:nbins) = pa_naerot(kk,ii,jj,1:nbins) + &
                    ( aero(1,1,1:nbins)%numc - aero_old(1,1,1:nbins)%numc )/pdn(kk,ii,jj)/tstep
               pa_ncloudt(kk,ii,jj,1:ncld) = pa_ncloudt(kk,ii,jj,1:ncld) + &
                    ( cloud(1,1,1:ncld)%numc - cloud_old(1,1,1:ncld)%numc )/pdn(kk,ii,jj)/tstep
               pa_nprecpt(kk,ii,jj,1:nprc) = pa_nprecpt(kk,ii,jj,1:nprc) + &
                    ( precp(1,1,1:nprc)%numc - precp_old(1,1,1:nprc)%numc )/pdn(kk,ii,jj)/tstep

               IF ( level == 5 ) THEN 
                  pa_nicet(kk,ii,jj,1:nice) = pa_nicet(kk,ii,jj,1:nice) + &
                       ( ice(1,1,1:nice)%numc - ice_old(1,1,1:nice)%numc )/pdn(kk,ii,jj)/tstep
               END IF

               ! Activated droplets
               pa_nactd(kk,ii,jj,1:ncld) = actd(1,1,1:ncld)%numc/pdn(kk,ii,jj)

               ! Get mass tendencies; loop over compounds
               DO nc = 1,iwa
                  
                  str = getMassIndex(nbins,1,nc)
                  end = getMassIndex(nbins,nbins,nc)
                  pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                       ( aero(1,1,1:nbins)%volc(nc) - aero_old(1,1,1:nbins)%volc(nc) )*spec%rholiq(nc)/pdn(kk,ii,jj)/tstep

                  str = getMassIndex(ncld,1,nc)
                  end = getMassIndex(ncld,ncld,nc)
                  pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                       ( cloud(1,1,1:ncld)%volc(nc) - cloud_old(1,1,1:ncld)%volc(nc) )*spec%rholiq(nc)/pdn(kk,ii,jj)/tstep

                  ! Activated droplets (in case of cloud base activation)
                  pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(nc)*spec%rholiq(nc)/pdn(kk,ii,jj)
                  
                  str = getMassIndex(nprc,1,nc)
                  end = getMassIndex(nprc,nprc,nc)
                  pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                       ( precp(1,1,1:nprc)%volc(nc) - precp_old(1,1,1:nprc)%volc(nc) )*spec%rholiq(nc)/pdn(kk,ii,jj)/tstep

               END DO

               ! ice and rimed ice
               IF ( level == 5 ) THEN

                  ! Dry species
                  DO nc = 1,ndry
                     str = getMassIndex(nice,1,nc)
                     end = getMassIndex(nice,nice,nc)
                     pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                          ( ice(1,1,1:nice)%volc(nc) - ice_old(1,1,1:nice)%volc(nc) )*spec%rhoice(nc)/pdn(kk,ii,jj)/tstep 
                  END DO

                  str = getMassIndex(nice,1,iwa)
                  end = getMassIndex(nice,nice,iwa)
                  str2 = getMassIndex(nice,1,irim)
                  end2 = getMassIndex(nice,nice,irim)

                  mprist_old(1:nice) = ice_old(1,1,1:nice)%volc(iwa) * &
                       spec%rhoic/pdn(kk,ii,jj)

                  mprist(1:nice) = ice(1,1,1:nice)%volc(iwa) * & 
                       spec%rhoic/pdn(kk,ii,jj)
                  
                  mrim_old(1:nice) = ice_old(1,1,1:nice)%volc(irim) * spec%rhori/pdn(kk,ii,jj)

                  mrim(1:nice) = ice(1,1,1:nice)%volc(irim) * spec%rhori/pdn(kk,ii,jj)

                  pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + (mprist - mprist_old)/tstep
                  pa_micet(kk,ii,jj,str2:end2) = pa_micet(kk,ii,jj,str2:end2) + (mrim - mrim_old)/tstep
                  
               END IF

               IF (lscndgas) THEN
                  pa_gaerot(kk,ii,jj,1) = pa_gaerot(kk,ii,jj,1) + &
                                          ( (zgso4(1,1)/pdn(kk,ii,jj)) - pa_gaerop(kk,ii,jj,1) )/tstep

                  pa_gaerot(kk,ii,jj,2) = pa_gaerot(kk,ii,jj,2) + &
                                          ( (zghno3(1,1)/pdn(kk,ii,jj)) - pa_gaerop(kk,ii,jj,2) )/tstep

                  pa_gaerot(kk,ii,jj,3) = pa_gaerot(kk,ii,jj,3) + &
                                          ( (zgnh3(1,1)/pdn(kk,ii,jj)) - pa_gaerop(kk,ii,jj,3) )/tstep

                  pa_gaerot(kk,ii,jj,4) = pa_gaerot(kk,ii,jj,4) + &
                                          ( (zgocnv(1,1)/pdn(kk,ii,jj)) - pa_gaerop(kk,ii,jj,4) )/tstep

                  pa_gaerot(kk,ii,jj,5) = pa_gaerot(kk,ii,jj,5) + &
                                          ( (zgocsv(1,1)/pdn(kk,ii,jj)) - pa_gaerop(kk,ii,jj,5) )/tstep
               END IF

               ! Tendency of water vapour mixing ratio 
               rt(kk,ii,jj) = rt(kk,ii,jj) + &
                  ( in_rv(1,1) - rv_old(1,1) )/tstep

            END DO ! kk
         END DO ! ii
      END DO ! jj

   END SUBROUTINE run_SALSA

   !
   !---------------------------------------------------------------
   ! SET_SALSA_RUNTIME
   ! Set the master process %state:s based on the values of %switch and %delay
   !
   ! Juha Tonttila, FMI, 2014
   !
   SUBROUTINE set_SALSA_runtime(time)
     USE mo_submctl, ONLY : Nmaster, lsmaster, lsfreeRH
     IMPLICIT NONE
     REAL, INTENT(in) :: time
     INTEGER :: i

     DO i = 1,Nmaster
        IF( lsmaster(i)%switch .AND. time > lsmaster(i)%delay ) lsmaster(i)%state = .TRUE.
     END DO

     ! Some other switches
     IF ( lsfreeRH%switch .AND. time > lsfreeRH%delay ) lsfreeRH%state = .TRUE.



   END SUBROUTINE set_SALSA_runtime


END MODULE mo_salsa_driver
