#|
  This file is a part of Clack package.
  URL: http://github.com/fukamachi/clack
  Copyright (c) 2011 Eitaro Fukamachi <e.arrows@gmail.com>

  Clack is freely distributable under the LLGPL License.
|#

#|
  Clack.Handler.Fcgi - Clack handler for FastCGI.

  Author: Eitaro Fukamachi (e.arrows@gmail.com)
|#

(in-package :cl-user)
(defpackage :clack-handler-mongrel2-asd
  (:use :cl :asdf))
(in-package :clack-handler-mongrel2-asd)

(defsystem clack-handler-mongrel2
  :version "0.0.1"
  :author "Jason Miller"
  :license "LLGPL"
  :depends-on (:clack
               :alexandria
               :flexi-streams
               :mymongrel2
               :quri)
  :components ((:file "mongrel2"))
  :description "Clack handler for Mongrel2")
