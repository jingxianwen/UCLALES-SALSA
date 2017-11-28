MODULE mo_salsa_driver

USE mo_submctl, ONLY : t_section
IMPLICIT NONE

!---------------------------------------------------------------
!
! MO_SALSA_DRIVER:
! Contains the primary SALSA input/output variables as well as
! subroutines used to call the main SALSA routine.
!
! Juha Tonttila, FMI, 2014
!
!---------------------------------------------------------------


  ! JT: Variables from SALSA
  ! --------------------------------------------
  ! grid points for SALSA
  INTEGER, PARAMETER :: kbdim = 1
  INTEGER, PARAMETER :: klev = 1

  REAL, PARAMETER :: init_rh(kbdim,klev) = 0.3

  ! -- Local hydrometeor properties (set up in aero initialize)
  TYPE(t_section), ALLOCATABLE :: cloud(:,:,:) ! cloud properties
  TYPE(t_section), ALLOCATABLE :: aero(:,:,:)  ! Aerosol properties
  TYPE(t_section), ALLOCATABLE :: precp(:,:,:) ! Precipitation properties
  TYPE(t_section), ALLOCATABLE :: ice(:,:,:) ! ice properties
  TYPE(t_section), ALLOCATABLE :: snow(:,:,:) ! snow aka. ice precip. properties

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
  SUBROUTINE run_SALSA(pnx, pny, pnz, n4, press, tk, rv, rt, rs, rsi, wp, pdn,   &
                       pa_naerop,  pa_naerot,  pa_maerop,  pa_maerot,   &
                       pa_ncloudp, pa_ncloudt, pa_mcloudp, pa_mcloudt,  &
                       pa_nprecpp, pa_nprecpt, pa_mprecpp, pa_mprecpt,  &
                       pa_nicep,   pa_nicet,   pa_micep,   pa_micet,    &
                       pa_nsnowp,  pa_nsnowt,  pa_msnowp,  pa_msnowt,   &
                       pa_nactd,   pa_vactd,   pa_gaerop,  pa_gaerot,   &
                       prunmode, prtcl, tstep, level)

    USE mo_submctl, ONLY : nbins,ncld,nprc,pi6,          &
                               nice,nsnw,             &
                               rhoic,rhosn,                  &
                               rhowa, rhosu, rhobc, rhooc,   &
                               rhono, rhonh, rhoss, rhodu,   &
                               rhlim, lscndgas, nlim, prlim
    USE mo_salsa, ONLY : salsa
    USE mo_salsa_properties, ONLY : equilibration
    USE class_componentIndex, ONLY : ComponentIndex, GetIndex, GetNcomp, IsUsed
    IMPLICIT NONE

    INTEGER, INTENT(in) :: pnx,pny,pnz,n4                       ! Dimensions: x,y,z,number of chemical species  
    REAL, INTENT(in)    :: tstep                      ! Model timestep length

    REAL, INTENT(in)    :: press(pnz,pnx,pny), &            ! Pressure (Pa)
                               tk(pnz,pnx,pny),    &            ! Temperature (K)
                               rv(pnz,pnx,pny),    &            ! Water vapor mixing ratio
                               rs(pnz,pnx,pny),    &            ! Water vapour saturation mixing ratio
                               rsi(pnz,pnx,pny),   &            ! Water vapour saturation mixing ratio over ice
                               wp(pnz,pnx,pny)                  ! Vertical velocity (m s-1)

    REAL, INTENT(in)    :: pdn(pnz,pnx,pny)             ! Air density (for normalizing concentrations)

    REAL, INTENT(in)    :: pa_naerop(pnz,pnx,pny,nbins),        & ! aerosol number concentration (# kg-1)
                               pa_maerop(pnz,pnx,pny,n4*nbins),     & ! aerosol mass concentration (kg kg-1)
                               pa_ncloudp(pnz,pnx,pny,ncld),        & ! Cloud droplet number concentration (# kg-1)
                               pa_mcloudp(pnz,pnx,pny,n4*ncld),     & ! Cloud droplet mass concentration (kg kg-1)
                               pa_nprecpp(pnz,pnx,pny,nprc),        & ! Rain drop number concentration (# kg-1)
                               pa_mprecpp(pnz,pnx,pny,n4*nprc),     & ! Rain drop mass concentration (kg kg-1)
                               pa_nicep(pnz,pnx,pny,nice),          & ! ice number concentration (# kg-1)
                               pa_micep(pnz,pnx,pny,n4*nice),       & ! ice mass concentration (kg kg-1)
                               pa_nsnowp(pnz,pnx,pny,nsnw),         & ! snow number concentration (# kg-1)
                               pa_msnowp(pnz,pnx,pny,n4*nsnw)         ! snow mass concentration (kg kg-1)

    REAL, INTENT(in)    :: pa_gaerop(pnz,pnx,pny,5)         ! Gaseous tracers [# kg]

    INTEGER, INTENT(in) :: prunmode                      ! 1: Initialization call
                                                         ! 2: Spinup period call
                                                         ! 3: Regular runtime call
    INTEGER, INTENT(in) :: level                         ! thermodynamical level

    TYPE(ComponentIndex), INTENT(in) :: prtcl ! Object containing the indices of different aerosol components for mass arrays

    REAL, INTENT(inout)   :: pa_naerot(pnz,pnx,pny,nbins),      & ! Aerosol number tendency
                                 pa_maerot(pnz,pnx,pny,n4*nbins),   & ! Aerosol mass tendency
                                 pa_ncloudt(pnz,pnx,pny,ncld),      & ! Cloud droplet number tendency
                                 pa_mcloudt(pnz,pnx,pny,n4*ncld),   & ! Cloud droplet mass tendency
                                 pa_nprecpt(pnz,pnx,pny,nprc),      & ! Rain drop number tendency
                                 pa_mprecpt(pnz,pnx,pny,n4*nprc),   & ! Rain drop mass tendency
                                 pa_nicet(pnz,pnx,pny,nice),        & ! Ice number tendency
                                 pa_micet(pnz,pnx,pny,n4*nice),     & ! Ice mass tendency
                                 pa_nsnowt(pnz,pnx,pny,nsnw),       & ! snow number tendency
                                 pa_msnowt(pnz,pnx,pny,n4*nsnw)       ! snow mass tendecy

    REAL, INTENT(inout)   :: pa_gaerot(pnz,pnx,pny,5)         ! Gaseous tracer tendency
    REAL, INTENT(inout)   :: rt(pnz,pnx,pny)                  ! Water vapour tendency

    REAL, INTENT(out)   :: pa_vactd(pnz,pnx,pny,n4*ncld) ! Volume concentrations of newly activated droplets for calculating the
                                                         ! actual tendency due to new droplet formation.
    REAL, INTENT(out)   :: pa_nactd(pnz,pnx,pny,ncld)   ! Same for number concentration

    TYPE(t_section) :: actd(kbdim,klev,ncld) ! Activated droplets - for interfacing with SALSA

    ! Helper arrays for calculating the rates of change
    TYPE(t_section) :: aero_old(1,1,nbins), cloud_old(1,1,ncld), precp_old(1,1,nprc), &
       ice_old(1,1,nice), snow_old(1,1,nsnw)

    INTEGER :: jj,ii,kk,ss,str,end, nc,vc
    REAL :: in_p(kbdim,klev), in_t(kbdim,klev), in_rv(kbdim,klev), in_rs(kbdim,klev),&
                in_w(kbdim,klev), in_rsi(kbdim,klev), in_pdn(kbdim,klev)
    REAL :: rv_old(kbdim,klev)

    ! Number is always set, but mass can be uninitialized
    DO ss = 1,GetNcomp(prtcl)+1
       actd(:,:,:)%volc(ss) = 0.
       aero(:,:,:)%volc(ss) = 0.
       cloud(:,:,:)%volc(ss) = 0.
       precp(:,:,:)%volc(ss) = 0.
       ice(:,:,:)%volc(ss) = 0.
       snow(:,:,:)%volc(ss) = 0.
       aero_old(:,:,:)%volc(ss) = 0.
       cloud_old(:,:,:)%volc(ss) = 0.
       precp_old(:,:,:)%volc(ss) = 0.
       ice_old(:,:,:)%volc(ss) = 0.
       snow_old(:,:,:)%volc(ss) = 0.
    END DO

    ! Set the SALSA runtime config
    CALL set_salsa_runtime(prunmode)

    ! Convert input concentrations for SALSA into #/m3 or m3/m3 instead of kg/kg (multiplied by pdn/divided by substance density)
    DO jj = 3,pny-2
       DO ii = 3,pnx-2
          DO kk = pnz-1,2,-1

             ! Set inputs
             in_p(1,1) = press(kk,ii,jj)
             in_t(1,1) = tk(kk,ii,jj)
             in_pdn(1,1) = pdn(kk,ii,jj)
             in_rs(1,1) = rs(kk,ii,jj)
             in_rsi(1,1) = rsi(kk,ii,jj)
             in_w(1,1) = wp(kk,ii,jj)

             ! For initialization and spinup, limit the RH with the parameter rhlim (assign in namelist.salsa)
             IF (prunmode < 3) THEN
                in_rv(1,1) = MIN(rv(kk,ii,jj), rs(kk,ii,jj)*rhlim)
             ELSE
                in_rv(1,1) = rv(kk,ii,jj)
             END IF
             rv_old(1,1) = in_rv(1,1)
                
             ! Set volume concentrations
             IF (IsUsed(prtcl,'SO4')) THEN
                nc = GetIndex(prtcl,'SO4')
                vc = 1
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosu
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosu
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosu
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosu
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosu
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'OC')) THEN
                nc = GetIndex(prtcl,'OC')
                vc = 2
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhooc
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhooc
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhooc
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhooc
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhooc
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'BC')) THEN
                nc = GetIndex(prtcl,'BC')
                vc = 3
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhobc
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhobc
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhobc
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhobc
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhobc
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'DU')) THEN
                nc = GetIndex(prtcl,'DU')
                vc = 4
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhodu
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhodu
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhodu
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhodu
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhodu
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'SS')) THEN
                nc = GetIndex(prtcl,'SS')
                vc = 5
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoss
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoss
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoss
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoss
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoss
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'NO')) THEN
                nc = GetIndex(prtcl,'NO')
                vc = 6
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhono
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhono
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhono
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhono
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhono
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             IF (IsUsed(prtcl,'NH')) THEN
                nc = GetIndex(prtcl,'NH')
                vc = 7
                str = (nc-1)*nbins+1
                end = nc*nbins
                aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhonh
                aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

                str = (nc-1)*ncld+1
                end = nc*ncld
                cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhonh
                cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

                str = (nc-1)*nprc+1
                end = nc*nprc
                precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhonh
                precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

                str = (nc-1)*nice+1
                end = nc*nice
                ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhonh
                ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

                str = (nc-1)*nsnw+1
                end = nc*nsnw
                snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhonh
                snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             END IF

             ! Water (always used)
             ! -----------------------------
             nc = GetIndex(prtcl,'H2O')
             vc = 8
             str = (nc-1)*nbins+1
             end = nc*nbins
             aero(1,1,1:nbins)%volc(vc) = pa_maerop(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhowa
             aero_old(1,1,1:nbins)%volc(vc) = aero(1,1,1:nbins)%volc(vc)

             str = (nc-1)*ncld+1
             end = nc*ncld
             cloud(1,1,1:ncld)%volc(vc) = pa_mcloudp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhowa
             cloud_old(1,1,1:ncld)%volc(vc) = cloud(1,1,1:ncld)%volc(vc)

             str = (nc-1)*nprc+1
             end = nc*nprc
             precp(1,1,1:nprc)%volc(vc) = pa_mprecpp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhowa
             precp_old(1,1,1:nprc)%volc(vc) = precp(1,1,1:nprc)%volc(vc)

             str = (nc-1)*nice+1
             end = nc*nice
             ice(1,1,1:nice)%volc(vc) = pa_micep(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhoic
             ice_old(1,1,1:nice)%volc(vc) = ice(1,1,1:nice)%volc(vc)

             str = (nc-1)*nsnw+1
             end = nc*nsnw
             snow(1,1,1:nsnw)%volc(vc) = pa_msnowp(kk,ii,jj,str:end)*pdn(kk,ii,jj)/rhosn
             snow_old(1,1,1:nsnw)%volc(vc) = snow(1,1,1:nsnw)%volc(vc)

             ! -----------------------------

             ! Number concentrations and particle sizes
             aero(1,1,1:nbins)%numc = pa_naerop(kk,ii,jj,1:nbins)*pdn(kk,ii,jj)
             aero_old(1,1,1:nbins)%numc = aero(1,1,1:nbins)%numc
             DO ss=1,nbins
                IF (aero(1,1,ss)%numc>nlim) THEN
                    aero(1,1,ss)%core = SUM(aero(1,1,ss)%volc(1:7))/aero(1,1,ss)%numc
                    aero(1,1,ss)%dwet = ( SUM(aero(1,1,ss)%volc(:))/aero(1,1,ss)%numc/pi6 )**(1./3.)
                ELSE
                    aero(1,1,ss)%dwet = aero(1,1,ss)%dmid
                    aero(1,1,ss)%core = pi6*(aero(1,1,ss)%dwet)**3
                ENDIF
             ENDDO

             cloud(1,1,1:ncld)%numc = pa_ncloudp(kk,ii,jj,1:ncld)*pdn(kk,ii,jj)
             cloud_old(1,1,1:ncld)%numc = cloud(1,1,1:ncld)%numc
             DO ss=1,ncld
                IF (cloud(1,1,ss)%numc>nlim) THEN
                    cloud(1,1,ss)%core = SUM(cloud(1,1,ss)%volc(1:7))/cloud(1,1,ss)%numc
                    cloud(1,1,ss)%dwet = ( SUM(cloud(1,1,ss)%volc(:))/cloud(1,1,ss)%numc/pi6 )**(1./3.)
                ELSE
                    cloud(1,1,ss)%dwet = cloud(1,1,ss)%dmid
                    cloud(1,1,ss)%core = pi6*(cloud(1,1,ss)%dwet)**3
                ENDIF
             ENDDO

             precp(1,1,1:nprc)%numc = pa_nprecpp(kk,ii,jj,1:nprc)*pdn(kk,ii,jj)
             precp_old(1,1,1:nprc)%numc = precp(1,1,1:nprc)%numc
             DO ss=1,nprc
                IF (precp(1,1,ss)%numc>prlim) THEN
                    precp(1,1,ss)%core = SUM(precp(1,1,ss)%volc(1:7))/precp(1,1,ss)%numc
                    precp(1,1,ss)%dwet = ( SUM(precp(1,1,ss)%volc(:))/precp(1,1,ss)%numc/pi6 )**(1./3.)
                ELSE
                    precp(1,1,ss)%dwet = precp(1,1,ss)%dmid
                    precp(1,1,ss)%core = pi6*(precp(1,1,ss)%dwet)**3
                ENDIF
             ENDDO

             ice(1,1,1:nice)%numc = pa_nicep(kk,ii,jj,1:nice)*pdn(kk,ii,jj)
             ice_old(1,1,1:nice)%numc = ice(1,1,1:nice)%numc
             DO ss=1,nice
                IF (ice(1,1,ss)%numc>prlim) THEN
                    ice(1,1,ss)%core = SUM(ice(1,1,ss)%volc(1:7))/ice(1,1,ss)%numc
                    ice(1,1,ss)%dwet = ( SUM(ice(1,1,ss)%volc(:))/ice(1,1,ss)%numc/pi6 )**(1./3.)
                ELSE
                    ice(1,1,ss)%dwet = ice(1,1,ss)%dmid
                    ice(1,1,ss)%core = pi6*(ice(1,1,ss)%dwet)**3
                ENDIF
             ENDDO

             snow(1,1,1:nsnw)%numc = pa_nsnowp(kk,ii,jj,1:nsnw)*pdn(kk,ii,jj)
             snow_old(1,1,1:nsnw)%numc = snow(1,1,1:nsnw)%numc
             DO ss=1,nsnw
                IF (snow(1,1,ss)%numc>prlim) THEN
                    snow(1,1,ss)%core = SUM(snow(1,1,ss)%volc(1:7))/snow(1,1,ss)%numc
                    snow(1,1,ss)%dwet = ( SUM(snow(1,1,ss)%volc(:))/snow(1,1,ss)%numc/pi6 )**(1./3.)
                ELSE
                    snow(1,1,ss)%dwet = snow(1,1,ss)%dmid
                    snow(1,1,ss)%core = pi6*(snow(1,1,ss)%dwet)**3
                ENDIF
             ENDDO


             ! If this is an initialization call, calculate the equilibrium particle
             If (prunmode == 1) CALL equilibration(kbdim,klev,   &
                                                    init_rh,in_t,aero,.TRUE.)


             ! Convert to #/m3
             zgso4(1,1) = pa_gaerop(kk,ii,jj,1)*pdn(kk,ii,jj)
             zghno3(1,1) = pa_gaerop(kk,ii,jj,2)*pdn(kk,ii,jj)
             zgnh3(1,1) = pa_gaerop(kk,ii,jj,3)*pdn(kk,ii,jj)
             zgocnv(1,1) = pa_gaerop(kk,ii,jj,4)*pdn(kk,ii,jj)
             zgocsv(1,1) = pa_gaerop(kk,ii,jj,5)*pdn(kk,ii,jj)

             ! ***************************************!
             !                Run SALSA               !
             ! ***************************************!
             CALL salsa(kbdim,  klev,          &
                        in_p,   in_rv,  in_rs,  in_rsi,        &
                        in_t,  tstep,                          &
                        zgso4,  zgocnv, zgocsv, zghno3,        &
                        zgnh3,  aero,   cloud,  precp,         &
                        ice,    snow,                          &
                        actd,   in_w,   prtcl, level, in_pdn)


             ! Calculate tendencies (convert back to #/kg or kg/kg)
             pa_naerot(kk,ii,jj,1:nbins) = pa_naerot(kk,ii,jj,1:nbins) + &
                  ( aero(1,1,1:nbins)%numc - aero_old(1,1,1:nbins)%numc )/pdn(kk,ii,jj)/tstep
             pa_ncloudt(kk,ii,jj,1:ncld) = pa_ncloudt(kk,ii,jj,1:ncld) + &
                  ( cloud(1,1,1:ncld)%numc - cloud_old(1,1,1:ncld)%numc )/pdn(kk,ii,jj)/tstep
             pa_nprecpt(kk,ii,jj,1:nprc) = pa_nprecpt(kk,ii,jj,1:nprc) + &
                  ( precp(1,1,1:nprc)%numc - precp_old(1,1,1:nprc)%numc )/pdn(kk,ii,jj)/tstep
             pa_nicet(kk,ii,jj,1:nice) = pa_nicet(kk,ii,jj,1:nice) + &
                  ( ice(1,1,1:nice)%numc - ice_old(1,1,1:nice)%numc )/pdn(kk,ii,jj)/tstep
             pa_nsnowt(kk,ii,jj,1:nsnw) = pa_nsnowt(kk,ii,jj,1:nsnw) + &
                  ( snow(1,1,1:nsnw)%numc - snow_old(1,1,1:nsnw)%numc )/pdn(kk,ii,jj)/tstep
             ! Activated droplets
             pa_nactd(kk,ii,jj,1:ncld) = actd(1,1,1:ncld)%numc/pdn(kk,ii,jj)

             IF (IsUsed(prtcl,'SO4')) THEN
                nc = GetIndex(prtcl,'SO4')
                vc = 1
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhosu/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhosu/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhosu/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhosu/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhosu/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhosu/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'OC')) THEN
                nc = GetIndex(prtcl,'OC')
                vc = 2
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhooc/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhooc/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhooc/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhooc/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhooc/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhooc/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'BC')) THEN
                nc = GetIndex(prtcl,'BC')
                vc = 3
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhobc/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhobc/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhobc/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhobc/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhobc/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhobc/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'DU')) THEN
                nc = GetIndex(prtcl,'DU')
                vc = 4
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhodu/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhodu/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhodu/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhodu/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhodu/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhodu/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'SS')) THEN
                nc = GetIndex(prtcl,'SS')
                vc = 5
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhoss/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhoss/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhoss/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhoss/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhoss/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhoss/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'NO')) THEN
                nc = GetIndex(prtcl,'NO')
                vc = 6
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhono/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhono/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhono/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhono/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhono/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhono/pdn(kk,ii,jj)
             END IF

             IF (IsUsed(prtcl,'NH')) THEN
                nc = GetIndex(prtcl,'NH')
                vc = 7
                ! Aerosol bins
                str = (nc-1)*nbins+1
                end = nc*nbins
                pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                     ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhonh/pdn(kk,ii,jj)/tstep
                ! Hydrometeor bins
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                     ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhonh/pdn(kk,ii,jj)/tstep
                ! Rain drops
                str = (nc-1)*nprc+1
                end = nc*nprc
                pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                     ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhonh/pdn(kk,ii,jj)/tstep
                ! Ice bins
                str = (nc-1)*nice+1
                end = nc*nice
                pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                     ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhonh/pdn(kk,ii,jj)/tstep
                ! Snow bins
                str = (nc-1)*nsnw+1
                end = nc*nsnw
                pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                     ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhonh/pdn(kk,ii,jj)/tstep
                ! Activated droplets
                str = (nc-1)*ncld+1
                end = nc*ncld
                pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhonh/pdn(kk,ii,jj)
             END IF

             ! Water (always used)
             ! ---------------------------------------
             nc = GetIndex(prtcl,'H2O')
             vc = 8
             ! Aerosol bins
             str = (nc-1)*nbins+1
             end = nc*nbins
             pa_maerot(kk,ii,jj,str:end) = pa_maerot(kk,ii,jj,str:end) + &
                  ( aero(1,1,1:nbins)%volc(vc) - aero_old(1,1,1:nbins)%volc(vc) )*rhowa/pdn(kk,ii,jj)/tstep
             ! Hydrometeor bins
             str = (nc-1)*ncld+1
             end = nc*ncld
             pa_mcloudt(kk,ii,jj,str:end) = pa_mcloudt(kk,ii,jj,str:end) + &
                  ( cloud(1,1,1:ncld)%volc(vc) - cloud_old(1,1,1:ncld)%volc(vc) )*rhowa/pdn(kk,ii,jj)/tstep
             ! Rain drops
             str = (nc-1)*nprc+1
             end = nc*nprc
             pa_mprecpt(kk,ii,jj,str:end) = pa_mprecpt(kk,ii,jj,str:end) + &
                  ( precp(1,1,1:nprc)%volc(vc) - precp_old(1,1,1:nprc)%volc(vc) )*rhowa/pdn(kk,ii,jj)/tstep
             ! Ice bins
             str = (nc-1)*nice+1
             end = nc*nice
             pa_micet(kk,ii,jj,str:end) = pa_micet(kk,ii,jj,str:end) + &
                  ( ice(1,1,1:nice)%volc(vc) - ice_old(1,1,1:nice)%volc(vc) )*rhoic/pdn(kk,ii,jj)/tstep
             ! Snow bins
             str = (nc-1)*nsnw+1
             end = nc*nsnw
             pa_msnowt(kk,ii,jj,str:end) = pa_msnowt(kk,ii,jj,str:end) + &
                  ( snow(1,1,1:nsnw)%volc(vc) - snow_old(1,1,1:nsnw)%volc(vc) )*rhosn/pdn(kk,ii,jj)/tstep
             ! Activated droplets
             str = (nc-1)*ncld+1
             end = nc*ncld
             pa_vactd(kk,ii,jj,str:end) = actd(1,1,1:ncld)%volc(vc)*rhowa/pdn(kk,ii,jj)
             ! ----------------------------------------

             IF (lscndgas) THEN
               pa_gaerot(kk,ii,jj,1) = pa_gaerot(kk,ii,jj,1) + &
                  ( zgso4(1,1)/pdn(kk,ii,jj) - pa_gaerop(kk,ii,jj,1) )/tstep

               pa_gaerot(kk,ii,jj,2) = pa_gaerot(kk,ii,jj,2) + &
                  ( zghno3(1,1)/pdn(kk,ii,jj) - pa_gaerop(kk,ii,jj,2) )/tstep

               pa_gaerot(kk,ii,jj,3) = pa_gaerot(kk,ii,jj,3) + &
                  ( zgnh3(1,1)/pdn(kk,ii,jj) - pa_gaerop(kk,ii,jj,3) )/tstep

               pa_gaerot(kk,ii,jj,4) = pa_gaerot(kk,ii,jj,4) + &
                  ( zgocnv(1,1)/pdn(kk,ii,jj) - pa_gaerop(kk,ii,jj,4) )/tstep

               pa_gaerot(kk,ii,jj,5) = pa_gaerot(kk,ii,jj,5) + &
                  ( zgocsv(1,1)/pdn(kk,ii,jj) - pa_gaerop(kk,ii,jj,5) )/tstep
             ENDIF

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
  ! Set logical switches according to the host model state and
  ! user-specified NAMELIST options.
  !
  ! Juha Tonttila, FMI, 2014
  !
  SUBROUTINE set_SALSA_runtime(prunmode)
    USE mo_submctl, ONLY : nlcoag,                 &
                               nlcgaa,nlcgcc,nlcgpp,   &
                               nlcgca,nlcgpa,nlcgpc,   &
                               nlcnd,                  &
                               nlcndgas,               &
                               nlcndh2oae, nlcndh2ocl, &
                               nlcndh2oic,             &
                               nlauto,nlautosnow,      &
                               nlactiv,                &
                               nlactbase,nlactintst,   &

                               lscoag,                 &
                               lscgaa,lscgcc,lscgpp,   &
                               lscgca,lscgpa,lscgpc,   &
                               lscnd,                  &
                               lscndgas,               &
                               lscndh2oae, lscndh2ocl, &
                               lscndh2oic,             &
                               lsauto,lsautosnow,      &
                               lsactiv,                &
                               lsactbase,lsactintst,   &

                               nlcgia,nlcgic,nlcgii,   &
                               nlcgip,nlcgsa,nlcgsc,   &
                               nlcgsi,nlcgsp,nlcgss,   &
                               nlcnd,                  &
                               nlicenucl,               &
                               nlicmelt,               &
                               nlfixinc,               &

                               lscgia,lscgic,lscgii,   &
                               lscgip,lscgsa,lscgsc,   &
                               lscgsi,lscgsp,lscgss,   &
                               lsicenucl,                &
                               lsicmelt,               &
                               lsfixinc

    IMPLICIT NONE

    INTEGER, INTENT(in) :: prunmode

    ! Apply runtime settings

    lscoag      = nlcoag
    lscgaa      = nlcgaa
    lscgcc      = nlcgcc
    lscgpp      = nlcgpp
    lscgca      = nlcgca
    lscgpa      = nlcgpa
    lscgpc      = nlcgpc
    lscgia      = nlcgia
    lscgic      = nlcgic
    lscgii      = nlcgii
    lscgip      = nlcgip
    lscgsa      = nlcgsa
    lscgsc      = nlcgsc
    lscgsi      = nlcgsi
    lscgsp      = nlcgsp
    lscgss      = nlcgss

    lscnd       = nlcnd
    lscndgas    = nlcndgas
    lscndh2oae  = nlcndh2oae
    lscndh2ocl  = nlcndh2ocl
    lscndh2oic  = nlcndh2oic

    lsauto      = nlauto
    lsautosnow  = nlautosnow

    lsactiv     = nlactiv
    lsactbase   = nlactbase
    lsactintst  = nlactintst

    lsicenucl  = ( nlicenucl .AND. ( .NOT. nlfixinc ) )
    lsfixinc    = nlfixinc
    lsicmelt    = nlicmelt


    ! Adjustments for initialization and spinup

    SELECT CASE(prunmode)

       CASE(1) ! Initialization

          lscoag      = .FALSE.
          lsauto      = .FALSE.
          lsautosnow  = .FALSE.
          lsactbase   = .FALSE.
          lsactintst  = nlactintst
          lsicenucl  = .FALSE.
          lsfixinc    = .FALSE.
          lsicmelt    = .FALSE.

       CASE(2)  ! Spinup period

          lscoag      = .FALSE.
          lsauto      = .FALSE.
          lsautosnow  = .FALSE.

    END SELECT

  END SUBROUTINE set_SALSA_runtime


END MODULE mo_salsa_driver
