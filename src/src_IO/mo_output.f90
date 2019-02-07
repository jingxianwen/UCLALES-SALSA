MODULE mo_output
  USE netcdf
  USE mpi_interface, ONLY : myid, ver, author, info
  USE ncio
  USE grid, ONLY : outAxes,outAxesPS,expnme,nzp,nxp,nyp,filprf,  &
                   lbinanl,level,lsalsabbins
  USE mo_field_types, ONLY : outProg, outVector, outDiag, outDerived, outPS
  USE classFieldArray, ONLY : FieldArray
  USE mo_structured_datatypes
  USE mo_submctl, ONLY : in1a,fn2a,in2b,fn2b,ica,fca,icb,fcb,nprc,nice
  
  IMPLICIT NONE

  LOGICAL :: sflg = .FALSE.
  REAL :: ps_intvl = 120.
  REAL :: main_intvl = 3600.
  INTEGER, PRIVATE :: ncid_main, ncid_ps
  INTEGER, PRIVATE :: nrec_main, nvar_main, nrec_ps, nvar_ps
  CHARACTER(len=150), PRIVATE :: fname_main, fname_ps      



  
  CONTAINS

    !
    ! ----------------------------------------------------------------------
    ! Subroutine init_main:  Defines the netcdf Analysis file
    !
    ! Modified for level 4.
    ! Juha Tonttila, FMI, 2014
    !
    !
    SUBROUTINE init_main(time)
      REAL, INTENT(in) :: time

      INTEGER :: npoints
      
      npoints = (nxp-4)*(nyp-4)

      fname_main = trim(filprf)

      IF ( .NOT. ANY([outProg%Initialized,     &
                      outDiag%Initialized,     &
                      outDerived%Initialized]  &
                    ) ) RETURN ! If no output variables defined, do not open the files 
      
      IF(myid == 0) PRINT                                                  &
           "(//' ',49('-')/,' ',/,'   Initializing: ',A20)",trim(fname_main)
      
      CALL open_nc(fname_main,expnme,time,npoints,ncid_main,nrec_main,ver,author,info)

      IF (level < 4 .OR. .NOT. lbinanl) THEN
         CALL define_nc(ncid_main,nrec_main,nvar_main,          &
                        outProg=outProg,outVector=outVector,    &
                        outDiag=outDiag,outDerived=outDerived,  &
                        outAxes=outAxes, n1=nzp,n2=nxp-4,n3=nyp-4)

      ELSE IF (level == 4 .AND. lbinanl) THEN
         IF (lsalsabbins) THEN           
            CALL define_nc(ncid_main,nrec_main,nvar_main,          &
                           outProg=outProg,outVector=outVector,    &
                           outDiag=outDiag,outDerived=outDerived,  &
                           outAxes=outAxes, n1=nzp,n2=nxp-4,       &
                           n3=nyp-4,inae_a=fn2a,inae_b=fn2b-fn2a,  &
                           incld_a=fca%cur,incld_b=fcb%cur,        &
                           inprc=nprc                              )
               
         ELSE              
            CALL define_nc(ncid_main,nrec_main,nvar_main,          &
                           outProg=outProg,outVector=outVector,    &
                           outDiag=outDiag,outDerived=outDerived,  &
                           outAxes=outAxes,n1=nzp,n2=nxp-4,        &
                           n3=nyp-4,inae_a=fn2a,incld_a=fca%cur,   &
                           inprc=nprc                              )    
            
         END IF
            
      ELSE IF (level == 5 .AND. lbinanl) THEN
         IF (lsalsabbins) THEN
            CALL define_nc(ncid_main,nrec_main,nvar_main,          &
                           outProg=outProg,outVector=outVector,    &
                           outDiag=outDiag,outDerived=outDerived,  &
                           outAxes=outAxes,n1=nzp,n2=nxp-4,        &
                           n3=nyp-4,inae_a=fn2a,inae_b=fn2b-fn2a,  &
                           incld_a=fca%cur,incld_b=fcb%cur,        &                              
                           inprc=nprc,inice=nice                   )
               
         ELSE
            CALL define_nc(ncid_main,nrec_main,nvar_main,          &
                           outProg=outProg,outVector=outVector,    &
                           outDiag=outDiag,outDerived=outDerived,  &
                           outAxes=outAxes,n1=nzp,n2=nxp-4,        &
                           n3=nyp-4,inae_a=fn2a,incld_a=fca%cur,   &                              
                           inprc=nprc,inice=nice                   )
         END IF
         
      END IF
               
      IF (myid == 0) PRINT *,'   ...starting record: ', nrec_main

      
    END SUBROUTINE init_main

    ! ------------------------------------------------------------------------

    SUBROUTINE init_ps(time)
      REAL, INTENT(in) :: time

      INTEGER :: npoints

      npoints = (nxp-4)*(nyp-4)
      
      fname_ps = TRIM(filprf)//'.ps'

      IF (.NOT. outPS%Initialized) RETURN ! If no variables defined for output, do not create the file 
      
      IF(myid == 0) PRINT                                                  &
           "(//' ',49('-')/,' ',/,'   Initializing: ',A20)",trim(fname_ps)

      CALL open_nc(fname_ps,expnme,time,npoints,ncid_ps,nrec_ps,ver,author,info)

      ! Providing the full outAxes will cause some error codes from netCDF when trying to
      ! define the vector variables for axes dimensions that are not defined for the netcdf
      ! file. This won't affect the model operation and it should work, but it would be
      ! better to somehow mask the outAxes variables for different output types.

      IF (level < 4 .OR. .NOT. lbinanl) THEN
         CALL define_nc(ncid_ps,nrec_ps,nvar_ps,         &
                        outPS=outPS,outAxes=outAxesPS,   &  ! Use the PS subset of the axis variables                               
                        n1=nzp                           )
      END IF

      IF (myid == 0) PRINT *,'   ...starting record: ', nrec_ps
      
    END SUBROUTINE init_ps

    ! -------------------------------------------------------------------------
    
    SUBROUTINE close_main()
      CALL close_nc(ncid_main)
    END SUBROUTINE close_main

    SUBROUTINE close_ps()
      CALL close_nc(ncid_ps)
    END SUBROUTINE close_ps
    
    !
    ! ----------------------------------------------------------------------
    ! Subroutine Write_main:  Writes the netcdf Analysis file
    !
    ! Modified for levels 4 and 5
    ! Juha Tonttila, FMI, 2014
    !
    !
    SUBROUTINE write_main(time)
      REAL, INTENT(in) :: time
      INTEGER :: ibeg0(1)

      ibeg0 = [nrec_main]

      IF ( .NOT. ANY([outProg%Initialized,     &
                      outDiag%Initialized,     &
                      outDerived%Initialized]  &
                    ) ) RETURN ! If no output variables defined, do not try to write
      
      ! write time
      CALL write_nc(ncid_main,'time',time,ibeg0)
      
      IF (nrec_main == 1) THEN
         ! First entry -> write axis variables
         CALL write_output(outAxes,nrec_main,ncid_main)
      END IF
      
      IF (outProg%Initialized) &
           CALL write_output(outProg,nrec_main,ncid_main)
      IF (outVector%Initialized) &
           CALL write_output(outVector,nrec_main,ncid_main)
      IF (outDiag%Initialized) &
           CALL write_output(outDiag,nrec_main,ncid_main)
      IF (outDerived%Initialized) &
           CALL write_output(outDerived,nrec_main,ncid_main)

      IF (myid == 0) PRINT "(//' ',12('-'),'   Record ',I3,' to: ',A60 //)",    &
         nrec_main,fname_main

      CALL sync_nc(ncid_main)
      nrec_main = nrec_main+1      
      
    END SUBROUTINE write_main

    ! --------------------------------------------------------------------------

    SUBROUTINE write_ps(time)
      REAL, INTENT(in) :: time
      INTEGER :: ibeg0(1)

      ibeg0 = [nrec_ps]

      IF ( .NOT. outPS%Initialized ) RETURN
      
      ! write time
      CALL write_nc(ncid_ps,'time',time,ibeg0)

      IF (nrec_ps == 1) THEN
         ! First entry -> write axis variables
         CALL write_output(outAxesPS,nrec_ps,ncid_ps)
      END IF

      IF (outPS%Initialized) &
           CALL write_output(outPS,nrec_ps,ncid_ps)

      IF (myid == 0) PRINT "(//' ',12('-'),'   Record ',I3,' to: ',A60 //)",    &
         nrec_ps,fname_ps      

      CALL sync_nc(ncid_ps)
      nrec_ps = nrec_ps+1
      
    END SUBROUTINE write_ps
    
    !
    ! Subroutine WRITE_OUTPUT: A general wrap-around routine used to to the writing of all kinds of
    !                          output variables
    !
    !
    SUBROUTINE write_output(varArray,nrec0,ncid0)
      TYPE(FieldArray), INTENT(in) :: varArray
      INTEGER, INTENT(in) :: ncid0
      INTEGER, INTENT(inout) :: nrec0
      
      INTEGER :: icnt0d(1), icnt0dsd(2), icnt1d(2), icnt1dsd(3), icnt2d(3), icnt3d(4), icnt3dsd(5) ! count arrays for 3d variables and 4d size distribution variables
      INTEGER :: ibeg0d(1), ibeg1d(2), ibeg2d(3), ibeg3d(4), ibeg4d(5) ! same for beginning indices

      CHARACTER(len=10) :: vname

      INTEGER :: n, nvar

      TYPE(FloatArray0d), POINTER :: var0d => NULL()
      TYPE(FloatArray1d), POINTER :: var1d => NULL()
      TYPE(FloatArray2d), POINTER :: var2d => NULL()
      TYPE(FloatArray3d), POINTER :: var3d => NULL()
      TYPE(FloatArray4d), POINTER :: var4d => NULL()

      REAL :: out3d(nzp,nxp,nyp)
      REAL :: out1d(nzp)
      
      INTEGER :: i1,i2,j1,j2,nstr,nend

      IF ( .NOT. varArray%Initialized) RETURN  ! No variables assigned
      
      i1 = 3; i2 = nxp-2
      j1 = 3; j2 = nyp-2
      
      ! for 3d outputs these are always the same
      icnt1d = [nzp,1]
      icnt2d = [nxp-4,nyp-4,1]
      icnt3d = [nzp,nxp-4,nyp-4,1]      
      !icntXsd has to be defined on a case by case basis!

      ibeg1d = [1,nrec0]
      ibeg2d = [1,1,nrec0]
      ibeg3d = [1,1,1,nrec0]
      ibeg0d = [nrec0]
      ibeg4d = [1,1,1,1,nrec0]
      
      nvar = varArray%count
      DO n = 1,nvar
         vname = varArray%list(n)%name
         SELECT CASE(varArray%list(n)%dimension)
         CASE('time')
            CALL varArray%getData(1,var0d,index=n)
            CALL write_nc(ncid0,vname,var0d%d,ibeg0d)
            
         CASE('zt','zm')
            CALL varArray%getData(1,var1d,index=n)
            CALL write_nc(ncid0,vname,var1d%d(:),ibeg0d)
            
         CASE('xt','xm')
            CALL varArray%getData(1,var1d,index=n)
            CALL write_nc(ncid0,vname,var1d%d(i1:i2),ibeg0d)
            
         CASE('yt','ym')
            CALL varArray%getData(1,var1d,index=n)
            CALL write_nc(ncid0,vname,var1d%d(j1:j2),ibeg0d)

         CASE('aea','aeb','cla','clb','prc','ice')
            CALL varArray%getData(1,var1d,index=n)
            CALL write_nc(ncid0,vname,var1d%d(:),ibeg0d)
            
         CASE('ztt','zmt')
            CALL varArray%getData(1,var1d,index=n)
            IF (ASSOCIATED(var1d%onDemand)) THEN
               CALL var1d%onDemand(vname,out1d)
            ELSE
               out1d = var1d%d
            END IF
            CALL write_nc(ncid0,vname,out1d(:),ibeg1d,icnt=icnt1d)

         CASE('xtytt')
            CALL varArray%getData(1,var2d,index=n)
            CALL write_nc(ncid0,vname,var2d%d(i1:i2,j1:j2),ibeg2d,icnt=icnt2d)
            
         CASE('zttaea','zttaeb','zttcla','zttclb','zttprc','zttice')
            CALL getSDdim(varArray%list(n)%dimension,nstr,nend)
            icnt1dsd = [nzp,nend-nstr+1,1]
            CALL varArray%getData(1,var2d,index=n)
            CALL write_nc(ncid0,vname,var2d%d(:,nstr:nend),ibeg2d,icnt=icnt1dsd)
            
         CASE('taea','taeb','tcla','tclb','tprc','tice')
            CALL getSDdim(varArray%list(n)%dimension,nstr,nend)
            icnt0dsd = [nend-nstr+1,1]
            CALL varArray%getData(1,var1d,index=n)
            CALL write_nc(ncid0,vname,var1d%d(nstr:nend),ibeg1d,icnt=icnt0dsd)
            
         CASE('tttt','mttt','tmtt','ttmt')
            CALL varArray%getData(1,var3d,index=n)
            IF (ASSOCIATED(var3d%onDemand)) THEN
               CALL var3d%onDemand(vname,out3d)
            ELSE
               out3d = var3d%d
            END IF            
            CALL write_nc(ncid0,vname,out3d(:,i1:i2,j1:j2),ibeg3d,icnt=icnt3d)
            
         CASE('ttttaea','ttttaeb','ttttcla','ttttclb','ttttprc','ttttice')
            CALL getSDdim(varArray%list(n)%dimension,nstr,nend)
            icnt3dsd = [nzp,nxp-4,nyp-4,nend-nstr+1,1]
            CALL varArray%getData(1,var4d,index=n)
            CALL write_nc(ncid0,vname,var4d%d(:,i1:i2,j1:j2,nstr:nend),ibeg4d,icnt=icnt3dsd)
                       
         END SELECT                  
      END DO
      
      var0d => NULL(); var1d => NULL(); var2d => NULL(); var3d => NULL(); var4d => NULL()
            
    END SUBROUTINE write_output

    SUBROUTINE getSDdim(dim,nstr,nend)
      CHARACTER(len=*), INTENT(in) :: dim
      INTEGER, INTENT(out) :: nstr,nend

      nstr = 0
      nend = 0
      
      SELECT CASE(dim)
      CASE('ttttaea','zttaea','taea')
         nstr = in1a; nend = fn2a
      CASE('ttttaeb','zttaeb','taeb')
         nstr = in2b; nend = fn2b
      CASE('ttttcla','zttcla','tcla')
         nstr = ica%cur; nend = fca%cur
      CASE('ttttclb','zttclb','tclb')
         nstr = icb%cur; nend = fcb%cur
      CASE('ttttprc','zttprc','tprc')
         nstr = 1; nend = nprc
      CASE('ttttice','zttice','tice')
         nstr = 1; nend = nice
      END SELECT
              
    END SUBROUTINE getSDdim
    
    
END MODULE mo_output
