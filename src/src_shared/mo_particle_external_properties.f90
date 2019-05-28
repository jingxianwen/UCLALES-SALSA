MODULE mo_particle_external_properties
  USE mo_submctl, ONLY : pi6, eps, rg, surfw0, grav, spec
  USE classSection, ONLY : Section
  IMPLICIT NONE

  ! This module contains a collection of function to calculate physical and thermodynamical particle properties,
  ! such as diameters, fall velocities, equilibirium saturation ratios at a droplet surface etc.
    
  CONTAINS
    
    !
    ! Function for calculating terminal velocities for different particle types and size ranges.
    !     Tomi Raatikainen (2.5.2017)
    !     - Changed from radius to diameter since ~the rest of the model
    !       as well as the calculations below take diameter anyway! -Juha
    REAL FUNCTION terminal_vel(diam,rhop,rhoa,visc,beta,flag)
      IMPLICIT NONE
      REAL, INTENT(in) :: diam, rhop ! Particle diameter and density
      REAL, INTENT(in) :: rhoa, visc, beta ! Air density, viscocity and Cunningham correction factor
      INTEGER, INTENT(IN) :: flag ! Parameter for identifying aerosol (1), cloud droplets (2), precip (3), ice (4)
      ! Constants
      REAL, PARAMETER :: rhoa_ref = 1.225 ! reference air density (kg/m^3)
      REAL, PARAMETER :: delta0 = 9.06, C0 = 0.292, Dcr = 134.e-6 ! Khvorostyanov and Curry 2002
      REAL, PARAMETER :: are = 1.85                               ! Khvorostyanov and Curry 2002
      REAL :: Avr, Bv
      
      
      terminal_vel = 0.
      IF( ANY(flag == [1,2,3,4])) THEN
         ! Aerosol and cloud and rain droplets
         IF (diam<80.0e-6) THEN
            ! Stokes law with Cunningham slip correction factor
            terminal_vel = (diam**2)*(rhop-rhoa)*grav*beta/(18.*visc)  ![m s-1]
         ELSE IF (diam<1.2e-3) THEN
            ! Droplets from 40 um to 0.6 mm: linear dependence on particle radius and a correction for reduced pressure
            !   R.R. Rogers: A Short Course in Cloud Physics, Pergamon Press Ltd., 1979.
            terminal_vel = 4.e3*diam*SQRT(rhoa_ref/rhoa)
         ELSE
            ! Droplets larger than 0.6 mm: square root dependence on particle radius and a correction for reduced pressure
            !   R.R. Rogers: A Short Course in Cloud Physics, Pergamon Press Ltd., 1979.
            ! Note: this is valid up to 2 mm or 9 m/s (at 1000 mbar), where droplets start to break
            terminal_vel = 2.01e2*SQRT( MIN(diam/2.,2.0e-3)*rhoa_ref/rhoa )
         END IF
      ELSE IF (flag==4) THEN   ! Ice
         
         ! Khvorostyanov and Curry 2002
         IF (diam < Dcr) THEN
            Avr = 16.*rhop*grav / ( 3.*C0*rhoa*visc*delta0**2 )
            Bv = 2.
         ELSE IF (diam > Dcr) THEN
            Avr = SQRT(2.) * are * SQRT( 4.*rhop*grav / ( 3.*rhoa ) )
            Bv = 0.5
         END IF

         terminal_vel = Avr * (0.5*diam)**Bv
         
         !! Ice crystal terminal fall speed from Ovchinnikov et al. (2014)
         !terminal_vel = 12.0*SQRT(diam)
      END IF

    END FUNCTION terminal_vel
    
    !
    ! Function for calculating effective (wet) radius for any particle type
    ! - Aerosol, cloud and rain are spherical
    ! - Snow and ice can be irregular and their densities can be size-dependent
    !
    ! Correct dimension is needed for irregular particles (e.g. ice) for calculating fall speed (deposition and coagulation)
    ! and capacitance (condensation). Otherwise spherical assumed. This function is overloaded for LES and SALSA environments.
    !
    FUNCTION calcDiamLES(ns,numc,mass,flag,sph)
      USE util, ONLY : getBinMassArray
      USE mo_ice_shape, ONLY : getDiameter
      USE mo_submctl, ONLY : pi6
      IMPLICIT NONE
      INTEGER, INTENT(IN) :: ns ! Number of species
      INTEGER, INTENT(IN) :: flag ! Parameter for identifying aerosol (1), cloud droplets (2), precip (3) and ice (4) particle phases
      REAL, INTENT(IN) :: numc, mass(ns)
      LOGICAL, OPTIONAL, INTENT(in) :: sph
      REAL :: calcDiamLES
      
      LOGICAL :: l_sph
      
      ! By default, calculate diameter assuming spherical particles (relevant for ice)
      l_sph = .TRUE.
      IF (PRESENT(sph)) l_sph = sph
      
      calcDiamLES=0.

      IF (numc < 1.e-15) RETURN
            
      IF (flag==4) THEN   ! Ice
         IF (l_sph) THEN
            ! Spherical equivalent for ice
            calcDiamLES = ( SUM(mass(1:ns)/spec%rhoice(1:ns))/numc/pi6 )**(1./3.)
         ELSE
            ! non-spherical ice
            ! Get the effective ice diameter, i.e. the max diameter for non-spherical ice            
            calcDiamLES = getDiameter( SUM(mass(1:ns-1)),mass(ns),numc )
         END IF
      ELSE
         ! Radius from total volume of a spherical particle or aqueous droplet
         calcDiamLES = ( SUM(mass(1:ns)/spec%rholiq(1:ns))/numc/pi6 )**(1./3.)
      ENDIF

    END FUNCTION calcDiamLES

    ! -------------------------------------------------

    !
    ! Function for calculating equilibrium water saturation ratio at droplet surface based on Köhler theory
    !
    REAL FUNCTION calcSweq(part,T)
      TYPE(Section), INTENT(in) :: part ! Any particle
      REAL, INTENT(IN) :: T ! Absolute temperature (K)
      REAL :: dwet
      
      REAL :: znw,zns ! Moles of water and soluble material
      REAL :: zvw, zvs, zvtot ! Volume concentrations of water and soluble material and total dry
      INTEGER :: iwa, ndry ! Index for water, number of "dry" species
      INTEGER :: i
      
      iwa = spec%getIndex("H2O")
      ndry = spec%getNSpec(type="dry")

      calcSweq = 0.
      IF (part%numc < part%nlim) RETURN
      
      ! Wet diameter  !! USE THE FUNCTIONS PROVIDED FOR THIS??
      dwet = (SUM(part%volc(:))/part%numc/pi6)**(1./3.)
      
      ! Equilibrium saturation ratio = xw*exp(4*sigma*v_w/(R*T*Dwet))
      
      znw = part%volc(iwa)*spec%rhowa/spec%mwa
      zvw = part%volc(iwa)
      zns = 0.
      zvs = 0.
      zvtot = 0.
      DO i = 1,ndry
         zns = zns + spec%diss(i)*part%volc(i)*spec%rholiq(i)/spec%MM(i)
         zvs = zvs + MIN(1.,spec%diss(i)) * part%volc(i) ! Use "diss" here just to select the soluble species
         zvtot = zvtot + part%volc(i)
      END DO
      
      ! Combine the two cases from original code since they're exactly the same??
      IF (zvw > 1.e-28*part%numc .OR. zvs > 1.e-28*part%numc) THEN
         ! Aqueous droplet OR dry partially soluble particle
         calcSweq = (znw/(zns+znw)) * exp(4.*surfw0*spec%mwa/(rg*T*spec%rhowa*dwet))
      ELSE IF (zvtot-zvs > 1.e-28*part%numc) THEN
         ! Dry insoluble particle
         calcSweq = exp(4.*surfw0*spec%mwa/(rg*T*spec%rhowa*dwet))
      ELSE
         ! Just add eps to avoid divide by zero
         calcSweq = (znw/(eps+zns+znw)) * exp(4.*surfw0*spec%mwa/(rg*T*spec%rhowa*dwet))
      END IF
      
    END FUNCTIOn calcSweq
    
  END MODULE mo_particle_external_properties
  
