# cl+lbfgs3

An Common Lisp FFI for the 2011 version of L-BFGS-B (C. Zhu, R. H. Byrd and J. Nocedal
1997).

This version of Fortran code is based on the version 3.0 (Remark on Algorithm 778,
J.L. Morales and J. Nocedal 2011), lightly modified by John C Nash for linking to
R language, taken from Nash's lbfgsb3c R package.

## Multi-threading support

This library supports being called simultaneously from different thread optimising
different functions. From the user's side, no locking is needed (of course if your
objective function or gradients do something unsafe you still need to lock).

The original Fortran code cannot be run concurrently even if objective functions
and gradients does only pure side-effect-free arithmetics, due to the use of
COMMON and SAVE etc in Fortran. To circumvant this, this pacakge `dlopen` and
`dlclose` every time the optimisation is requested.

On Linux, you can only have as many threads as maximum usable amount of file
descriptors because we mmap to a file descriptor to pass to dlopen, and glibc
path-caches dlopen, forcing us to wait till the time for dlclose before we can
close the file descriptor. I don't know if this caching means they have to
share memory; for safety reason we wait.

On FreeBSD there's no such restriction.

## Supported platforms

LispWorks, SBCL, ClozureCL on Linux and FreeBSD.

## Extending to other platforms

If you are interested in making it work on Mac or Windows, take a look
at linking.c. I am not proficient enough in Mac and Windows (nor have access to)
to know how `load_library_from_memory` should look like in those platforms.
Contribution is welcome.

## Notes on usage

When using this library, make sure all returned by your function are `double-float`.

It is okay to throw signals etc in your objective function and gradients. If gradients
isn't supplied a simple finite diff is used to approximate it, but it does not do anything
especially sophisticated; if you experience numerical problems, you are advised to use
a better algorithm for gradient approximation.

SBCL has [systematically broken ISO/IEC 10967-2:2001 conformance](https://bugs.launchpad.net/sbcl/+bug/2160268)
and qNaN sometimes can throw. The link above is about log, but as of 2026 many other
math functions that has a range check is broken when it comes to qNaN. Also, SBCL
does some low-level signalling for invalid floating point operations, even if this
happens in a foreign library. For all these reasons, you must `handler-case` against 
your objective function and gradients on SBCL. For serious numerical work with
complicated likelihood from messy data, Clozure or one of commercial implementation
would perhaps give you less surprises.

## Example

### Rosenbrock, unconstrained

```lisp
(defun rosenbrock (x)
  (let ((x1 (aref x 0)) (x2 (aref x 1)))
    (+ (expt (- 1 x1) 2)
       (* 100 (expt (- x2 (* x1 x1)) 2)))))

(defun rosenbrock-grad (x)
  (let ((x1 (aref x 0)) (x2 (aref x 1)))
    (vector (+ (* -2 (- 1 x1))
               (* -400 x1 (- x2 (* x1 x1))))
            (* 200 (- x2 (* x1 x1))))))

(let ((res (lbfgsb3 #'rosenbrock
                    #(-1.2d0 1.0d0)
                    :gr #'rosenbrock-grad
                    :m 5
                    :factr 0d0
                    :pgtol 1d-5
                    :iprint 1
                    :trace nil)))
  (format t "x       = ~A~%" (lbfgsb3-result-x res))
  (format t "f       = ~A~%" (lbfgsb3-result-f res))
  (format t "n-iter  = ~A~%" (lbfgsb3-result-n-iter res))
  (format t "n-fg    = ~A~%" (lbfgsb3-result-n-fg res))
  (format t "message = ~A~%" (lbfgsb3-result-message res)))
```

### Quadratic, constrained

```lisp
(lbfgsb3 (lambda (x) (reduce #'+ (map 'vector #'* x x)))
         (make-array 5 :element-type 'double-float :initial-element 1d0)
         :lower (make-array 5 :element-type 'double-float :initial-element 0.1234d0)
         :upper (make-array 5 :element-type 'double-float :initial-element  2d0))
```

## API

## `lbfgsb3`

```lisp
(lbfgsb3 fn x0
         &key gr lower upper
              (m 10) (factr 1d7) (pgtol 1d-5)
              (max-iter 200) (max-fg 2500)
              (iprint -1) (trace nil))
```

### Arguments

| Argument   | Meaning |
|------------|---------|
| `fn`       | Objective function of one argument (the point vector). Must return a double-float. |
| `x0`       | Initial point (simple-array double-float). |
| `gr`       | Optional gradient function.  If `nil`, a numerical gradient is used. |
| `lower`    | Lower bounds (same length as `x0`).  Use `-1d300` (or similar) for unbounded. |
| `upper`    | Upper bounds (same length as `x0`).  Use `+1d300` for unbounded. |
| `m`        | Number of limited-memory corrections (typically 3–20). |
| `factr`    | Convergence tolerance factor relative to machine epsilon. |
| `pgtol`    | Projected-gradient tolerance.  Iteration stops when max |proj g_i| ≤ pgtol. |
| `max-iter` | Maximum number of iterations. |
| `max-fg`   | Maximum number of function/gradient evaluations. |
| `iprint`   | Fortran print level (`-1` = silent, `0` = final only, positive = more verbose). |
| `trace`    | When non-`nil`, enables all Fortran diagnostic output irrespective of `iprint`. |

### Return values

A struct of type

```lisp
(defstruct lbfgsb3-result
  x                      ; final point (simple-vector of double-float)
  f                      ; final function value
  g                      ; final gradient
  task                   ; final itask code
  n-iter                 ; number of iterations (isave[29] in 0-based)
  n-fg                   ; number of function/gradient evaluations
  message)               ; human-readable termination message
```
