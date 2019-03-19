!----------------------------------------------------------------------------
! This file is part of UCLALES.
!
! UCLALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! UCLALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
! Copyright 1999-2007, Bjorn B. Stevens, Dep't Atmos and Ocean Sci, UCLA
!----------------------------------------------------------------------------
!
program ucla_les

  use mpi_interface, ONLY : myid

  implicit none

  real :: t1, t2

  call cpu_time(t1)
  call driver
  call cpu_time(t2)

  if (myid == 0) THEN
    print "(/,' ',49('-')/,' ',A16,F10.1,' s')", '  Execution time: ', t2-t1
    stop ' ..... Normal termination'
  ENDIF

contains

  !----------------------------------------------------------------------
  ! Subroutine Driver:  This is the main program driver.  It calls routines
  ! to read the model initialization file, and configure memory and pointes.
  ! It also calls the routines which initialize the model and timestep it.
  !
  subroutine driver

    use grid, only          : define_grid, define_vars, level, nxp, nyp, nzp, nxpart
    use init, only          : initialize
    use step, only          : stepper
    use mpi_interface, only : init_mpi, define_decomp,                    &
         init_alltoall_reorder, appl_finalize

    ! Added for SALSA
    USE mo_salsa_init, ONLY : define_salsa, salsa_initialize

    implicit none

    integer ierror

    call init_mpi

    call define_parm

    IF (level >= 4) CALL define_salsa(level) ! Read SALSA namelist etc.

    IF (level >= 4) CALL salsa_initialize ! All salsa variables are now initialized

    call define_decomp(nxp, nyp, nxpart)

    call define_grid

    call init_alltoall_reorder(nxp, nyp, nzp)

    call define_vars

    call initialize ! Added initialization of aerosol size distributions here + a single call
                    ! for SALSA to set up cloud microphysics
    call stepper

    call appl_finalize(ierror)

    return
  end subroutine driver

  !
  ! ----------------------------------------------------------------------
  ! Subroutine Read_nl: Driver for reading model namelist
  !
  subroutine define_parm

    use util, only : fftinix,fftiniy
    use sgsm, only : csx, prndtl
    use srfc, only : isfctyp, zrough, ubmin, dthcon, drtcon
    use step, only : timmax, istpfl, corflg, outflg, frqanl, anl_start, frqhis, &
         strtim, radfrq, cntlat
    use grid, only : deltaz, deltay, deltax, nzp, nyp, nxp, nxpart, &
         dtlong, dzrat,dzmax, th00, umean, vmean, isgstyp, naddsc, level,     &
         filprf, expnme, iradtyp, igrdtyp, nfpt, distim, runtype, CCN,        &
         Tspinup, sst, lbinanl, lbinprof, sed_aero, sed_cloud, sed_precp, sed_ice, sed_snow, &
         stat_micro, stat_micro_ts, stat_micro_ps, &
         nudge_theta, nudge_theta_time, nudge_theta_zmin, nudge_theta_zmax, nudge_theta_tau, &
         nudge_rv, nudge_rv_time, nudge_rv_zmin, nudge_rv_zmax, nudge_rv_tau,  &
         nudge_u, nudge_u_time, nudge_u_zmin, nudge_u_zmax, nudge_u_tau,  &
         nudge_v, nudge_v_time, nudge_v_zmin, nudge_v_zmax, nudge_v_tau,  &
         nudge_ccn, nudge_ccn_time, nudge_ccn_zmin, nudge_ccn_zmax, nudge_ccn_tau
    use init, only : us, vs, ts, rts, ps, hs, ipsflg, itsflg,iseed, hfilin,   &
         zrand, zrndamp, zrndampq, zrandnorm
    use stat, only : ssam_intvl, savg_intvl, mcflg, csflg
    USE forc, ONLY : radsounding, &        ! Juha: added for radiation background profile
                     div, case_name, &     ! Divergence, forcing case name
                     sfc_albedo, &         ! Surface albedo
                     useMcICA,RadConstPress,RadPrecipBins,RadSnowBins
    use mpi_interface, only : myid, appl_abort, ver, author

    implicit none

    namelist /model/  &
         expnme    ,       & ! experiment name
         nxpart    ,       & ! whether partition in x direction?
         naddsc    ,       & ! Number of additional scalars
         savg_intvl,       & ! output statistics frequency
         ssam_intvl,       & ! integral accumulate/ts print frequency
         mcflg,            & ! Mass conservation stats flag
         csflg,            & ! Column statistics flag
         corflg , cntlat , & ! coriolis flag
         nfpt   , distim , & ! rayleigh friction points, dissipation time
         level  , CCN    , & ! Microphysical model Number of CCN per kg of air
         iseed  , zrand  , zrndamp, zrndampq, zrandnorm, & ! random seed
         nxp    , nyp    , nzp   ,  & ! number of x, y, z points
         deltax , deltay , deltaz , & ! delta x, y, z (meters)
         dzrat  , dzmax  , igrdtyp, & ! stretched grid parameters
         timmax , dtlong , istpfl , & ! timestep control
         runtype, hfilin , filprf , & ! type of run (INITIAL or HISTORY)
         frqhis , frqanl , outflg , & ! freq of history/anal writes, output flg
         anl_start,                 & ! start saving data to the 4D analysis files after this time
         iradtyp, radfrq , strtim , & ! radiation type flag
         isfctyp, ubmin  , zrough , & ! surface parameterization type
         sst    , dthcon , drtcon , & ! SSTs, surface flx parameters
         isgstyp, csx    , prndtl , & ! SGS model type, parameters
         ipsflg , itsflg ,          & ! sounding flags
         hs     , ps     , ts    ,  & ! sounding heights, pressure, temperature
         us     , vs     , rts   ,  & ! sounding E/W winds, water vapor
         umean  , vmean  , th00,    & ! gallilean E/W wind, basic state
         Tspinup, lbinanl, lbinprof, & ! Length of spinup period in seconds
         stat_micro, stat_micro_ts, stat_micro_ps, & ! Save statistics about microphysical process rates
         nudge_theta, nudge_theta_time, nudge_theta_zmin, nudge_theta_zmax, nudge_theta_tau, & ! Temperature nudging
         nudge_rv, nudge_rv_time, nudge_rv_zmin, nudge_rv_zmax, nudge_rv_tau, & ! Water vapor mixing ratio nudging
         nudge_u, nudge_u_time, nudge_u_zmin, nudge_u_zmax, nudge_u_tau, & ! Horizontal wind nudging
         nudge_v, nudge_v_time, nudge_v_zmin, nudge_v_zmax, nudge_v_tau, & ! Horizontal wind nudging
         nudge_ccn, nudge_ccn_time, nudge_ccn_zmin, nudge_ccn_zmax, nudge_ccn_tau, & ! Aerosol number concentration nudging
         radsounding, div, case_name, & ! Name of the radiation sounding file, divergence for LEVEL 4
         sfc_albedo,                  & ! Surface albedo
         useMcICA,           & ! Use the Monte Carlo Independent Column Approximation method (T/F)
         RadConstPress,      & ! keep constant pressure levels (T/F),
         RadPrecipBins,      & ! add precipitation bins to cloud water (0, 1, 2, 3,...)
         RadSnowBins,        & ! add snow bins to cloud ice (0, 1, 2, 3,...)
         sed_aero, sed_cloud, sed_precp, sed_ice, sed_snow ! Sedimentation (T/F)

    namelist /version/  &
         ver, author        ! Information about UCLALES-SALSA version and author

    ps       = 0.
    ts       = th00
    !
    ! these are for initializing the temp variables used in ffts in x and y
    ! directions.
    !
      fftinix=1
      fftiniy=1
    !
    ! read namelist from specified file
    !
    open  (1,status='old',file='NAMELIST')
    read  (1, nml=version)
    read  (1, nml=model)
    close (1)

    !
    ! write file variable control to standard output
    !
    if (myid == 0) then
       if (runtype == 'HISTORY') then
          write (*,601) expnme, hfilin, timmax
       else
          write (*,600) expnme, timmax
       end if
       if (outflg) write (*,602) filprf, frqhis, frqanl, Tspinup
       !
       ! do some cursory error checking in namelist variables
       !

       if (min(nxp,nyp) < 5) then
          if (myid == 0) print *, '  ABORTING: min(nxp,nyp) must be > 4.'
          call appl_abort(0)
       endif

       if (nzp < 3 ) then
          if (myid == 0) print *, '  ABORTING: nzp must be > 2 '
          call appl_abort(0)
       endif

       if (cntlat < -90. .or. cntlat > 90.) then
          if (myid == 0) print *, '  ABORTING: central latitude out of bounds.'
          call appl_abort(0)
       endif
    end if

600 format(//' ',49('-')/,' ',/,'  Initial Experiment: ',A50 &
         /,'  Final Time:         ',F8.1,' s'              )
601 format(//' ',49('-')/,' ',/,'  Restart Experiment: ',A50 &
         /,'  Restart File: ',A30,                           &
         /,'  Final Time: ',F10.1,' s'              )
602 format('  Output File Stem:   ',A50                      &
         /,'  History Frequency:  ',F7.1,                    &
         /,'  Analysis Frequency: ',F7.1,                    &
         /,'  Model spinup period: ',F7.1)

    return
  end subroutine define_parm

end program ucla_les

