(in-package #:cl+lbfgsb3)

(cffi:define-foreign-library liblinking
  (t "liblinking.so"))

(defun ensure-linking-loaded ()
  (let ((dir (asdf:system-relative-pathname "cl+lbfgsb3" "lib/")))
    (pushnew dir cffi:*foreign-library-directories* :test #'equal)
    (cffi:use-foreign-library liblinking)))

(ensure-linking-loaded)

(cffi:defctype linking-t :pointer)

(cffi:defcfun ("load_library_from_memory" %load-library-from-memory)
    linking-t
  (bytes :pointer)
  (len   :size))

(cffi:defcfun ("unload_library_from_memory" %unload-library-from-memory)
    :void
  (lib linking-t))

(cffi:defcfun ("memlib_dlsym" %linking-dlsym)
    :pointer
  (lib    linking-t)
  (symbol :string))

(defvar *lbfgsb3-so-bytes* nil)
(defvar *lbfgsb3-so-bytes-lock* (bt:make-lock "LBFGSB3-SO-BYTES"))
(defvar *fortran-prints-enabled*)

(defun ensure-so-bytes ()
  (bt:with-lock-held (*lbfgsb3-so-bytes-lock*)
    (unless *lbfgsb3-so-bytes*
      (let ((path (asdf:system-relative-pathname
                   "cl+lbfgsb3" "lib/liblbfgsb3.so")))
        (unless (probe-file path)
          (error "Cannot find ~A" path))
        (with-open-file (in path :element-type '(unsigned-byte 8)
                                 :direction :input)
          (let* ((len  (file-length in))
                 (buf  (make-array len :element-type '(unsigned-byte 8)
                                       #+lispworks
                                       :allocation
                                       #+lispworks
                                       :static)))
            (read-sequence buf in)
            (setf *lbfgsb3-so-bytes* buf)
            ;; (format t "~&[linking] loaded ~A bytes of liblbfgsb3.so into memory~%"
            ;;         len)
            ))))
    *lbfgsb3-so-bytes*))

(defun call-setulb-from-memory
    (n m x l u nbd f g factr pgtol wa iwa itask iprint
     icsave lsave isave dsave)
  "Load the library from the in-memory .so, call setulb_, then unload."
  (ensure-so-bytes)
  (let ((lib nil))
    (unwind-protect
         (progn
           ;; The pointer is only needed for the duration of the load;
           ;; the C side copies the bytes into a memfd / shm.
           (cffi:with-pointer-to-vector-data (ptr *lbfgsb3-so-bytes*)
             (setf lib (%load-library-from-memory
                        ptr (length *lbfgsb3-so-bytes*))))
           (when (or (null lib) (cffi:null-pointer-p lib))
             (error "load_library_from_memory failed~@[ : ~A~]"
                    (ignore-errors
                     (cffi:foreign-funcall "dlerror" :string))))
           (let ((fn (%linking-dlsym lib "setulb_")))
             (when (cffi:null-pointer-p fn)
               (error "linking_dlsym(\"setulb_\") failed"))
             (let ((flag (%linking-dlsym lib "printctrl_")))
               (unless (cffi:null-pointer-p flag)
                 (setf (cffi:mem-ref flag :int)
                       (if *fortran-prints-enabled* 1 0))))
             (cffi:foreign-funcall-pointer fn ()
               :pointer n
               :pointer m
               :pointer x
               :pointer l
               :pointer u
               :pointer nbd
               :pointer f
               :pointer g
               :pointer factr
               :pointer pgtol
               :pointer wa
               :pointer iwa
               :pointer itask
               :pointer iprint
               :pointer icsave
               :pointer lsave
               :pointer isave
               :pointer dsave
               :void)))
      (when (and lib (not (cffi:null-pointer-p lib)))
        (%unload-library-from-memory lib)))))

(defun setulb (n m x l u nbd f g factr pgtol wa iwa
               itask iprint icsave lsave isave dsave)
  (call-setulb-from-memory
   n m x l u nbd f g factr pgtol wa iwa
   itask iprint icsave lsave isave dsave))

