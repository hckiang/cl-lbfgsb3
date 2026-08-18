(defpackage #:cl+lbfgsb3-system
  (:use #:cl #:asdf))

(in-package #:cl+lbfgsb3-system)

(defclass makefile (source-file)
  ((type :initform nil)))

(defmethod perform ((o load-op) (c makefile))
  t)

(defmethod perform ((o compile-op) (c makefile))
  (let* ((fortran-dir (asdf:component-pathname (asdf:component-parent c)))
         (lib-dir     (merge-pathnames "../lib/" fortran-dir))
         (lib-name    "liblbfgsb3.so")
         (lib         (merge-pathnames lib-name lib-dir)))
    (ensure-directories-exist lib-dir)
    (format *error-output* "~&; Building ~A (in ~A) ...~%" lib fortran-dir)
    (uiop:run-program
     (list #+freebsd "gmake"
           #-freebsd "make"
           "-C" (uiop:native-namestring fortran-dir))
     :output t
     :error-output t)
    (unless (probe-file lib)
      (error "Makefile did not produce ~A" lib))))

(defmethod output-files ((o compile-op) (c makefile))
  (let* ((fortran-dir (component-pathname c))
         (lib-dir     (merge-pathnames "../lib/" fortran-dir)))
    (list (merge-pathnames
           #+darwin "liblbfgsb3.dylib"
           #+(and unix (not darwin)) "liblbfgsb3.so"
           #+(or windows win32) "lbfgsb3.dll"
           #-(or darwin unix windows win32) "liblbfgsb3.so"
           lib-dir))))

(defsystem "cl+lbfgsb3"
  :description "CFFI bindings to L-BFGS-B 3.0 (automatic Fortran build)"
  :author "Woodrow Hao Chi Kiang"
  :license "BSD 3-Clause"
  :depends-on ("cffi" "float-features" "bordeaux-threads")
  :serial t
  :components
  ((:module "foreign"
    :components ((:makefile "Makefile")))
   (:module "src"
    :components
    ((:file "package")
     (:file "linking")
     (:file "lbfgsb3-ffi")))))

(defsystem "cl+lbfgsb3/test"
  :depends-on ("cl+lbfgsb3"
               "bordeaux-threads"
               "fiveam")
  :serial t
  :components ((:module "test"
                :components
                ((:file "package")
                 (:file "concurrent-fit-rosenbrock")
                 (:file "suite"))))       ; optional
  :perform (test-op (o c)
             (uiop:symbol-call :cl+lbfgsb3/test :run-tests)))
