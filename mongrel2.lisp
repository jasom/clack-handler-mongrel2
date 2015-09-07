#|
  Copyright (c) 2015 Jason Miller

  Freely distributable under the LLGPL License.
|#

(in-package :cl-user)
(defpackage clack.handler.mongrel2
  (:export #:run #:stop)
  (:use :cl :mymongrel2)
  (:import-from :quri
                :url-decode)
  (:import-from :alexandria
                :make-keyword
                :when-let)
  (:import-from :flexi-streams
                :make-flexi-stream
                :make-in-memory-input-stream
                :string-to-octets))
(in-package :clack.handler.mongrel2)


(defun do-nothing ())

(defun one-thread (app cid sub-addr pub-addr debug context)
  (handler-case
      (with-connection (conn cid sub-addr pub-addr context)
	(loop
	   (let ((req (recv)))
	     (when (not (request-disconnectp req))
	       (let* ((env (handle-request req))
		      (res
		       (if debug
			   (funcall app env)
			   (handler-case (funcall app env)
			     (error (error)
			       (princ error *error-output*)
			       '(500 () ("Internal Server Error")))))))
		 (etypecase res
		   (list (handle-response req res))
		   (function (funcall res (lambda (res) (handle-response req res))))))))))
    ;;We shutdown workers by terminating the zmq context
    ;;This will cause any zeromq operations to return ETERM
    (pzmq:eterm () nil)))

(defun run (app &key (debug t) (port 0)
		  (threads 4)
		  (id-prefix "a-clack-server-")
		  (sub-addr "tcp://127.0.0.1:9997")
		  (pub-addr "tcp://127.0.0.1:9996")
		  (worker-entry #'do-nothing)
		  (worker-exit #'do-nothing))
  "Start Mongrel2 handler."
  (declare (ignore port))
  (let ((acceptor (pzmq:ctx-new)))
    (loop for i from 0 below threads
       for id = (format nil "~A~D" id-prefix i)
       do (bt:make-thread
	   (lambda ()
	     (unwind-protect
		  (progn
		    (funcall worker-entry)
		    (one-thread app id sub-addr pub-addr debug acceptor))
	       (funcall worker-exit)))
	   :name id))
    acceptor))


(defun stop (acceptor)
  (pzmq:ctx-destroy acceptor))

(defun slurp-file (pathname)
  (with-open-file (stream pathname
			  :direction :input
			  :element-type '(unsigned-byte 8))
    (let ((buf (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence buf stream)
      buf)))

(defun handle-response (req res)
  (let ((no-body #()))
    (destructuring-bind (status headers &optional (body no-body)) res
      (let ((headers
	     (loop for (k v) on headers by #'cddr
		with hash = (make-hash-table :test #'eq)
		if (gethash k hash)
		do (setf (gethash k hash)
			 (concatenate 'string (gethash k hash) ", " v))
		else
		do (setf (gethash k hash) v)
		finally
		  (progn
		    (remhash :content-length hash)
		    (return (alexandria:hash-table-alist hash))))))
	(let ((body
	       (cond
		 ((eql body no-body)
		  no-body)
		 ;;TODO could send file in chunks
		 ((pathnamep body)
		  (slurp-file body))
		 ((listp body)
		  (flex:string-to-octets (format nil "~{~A~%~%~}" body)
					 :external-format :utf-8))
		 ((typep body '(vector (unsigned-byte 8)))
		  body)
		 ((null body) "")
		 (t (error "Unknown body type")))))
	  (when (eq body no-body)
	    (reply-start-chunk req
			       :code status
			       :status (http-status-reason status)
			       :headers headers)
	    (return-from handle-response
	      (lambda (body &key (close nil))
		(when (> (length body) 0)
		  (mymongrel2::reply-a-chunk req (mymongrel2::bytes-to-string body)))
		(when close
		  (reply-finish-chunk req)
		  (when (request-closep req) (reply-close req))))))
	  (reply-http req body
		      :code status
		      :status (http-status-reason status)
		      :headers headers))))))

(defun handle-request (req)
  "Convert Request from server into a plist
before passing to Clack application."
  ;;(format *error-output* "Headers: ~S" (request-headers req))
  ;;(format *error-output* "~S" (assoc :body (request-headers req)))
  (let ((headers (make-hash-table :test 'equalp)))
    (flet ((set-header (k v)
	     (let ((k (string k)))
	       (multiple-value-bind (current existsp)
		   (gethash k headers)
		 (setf (gethash k headers)
		       (if existsp
			   (format nil "~A, ~A" v current)
			   v))))))
      (loop for (key . value) in (request-headers req)
	 when (not (upper-case-p (char (string key) 0)))
	 do (set-header key value))
      (let ((env (list :headers headers)))
	(push (make-keyword (cdr (assoc :method (request-headers req)))) env)
	(push :request-method env)
	(push "" env)
	(push :script-name env)
	(push (cdr (assoc :path (request-headers req))) env)
	(push :path-info env)
	(when (cdr (assoc :uri (request-headers req)))
	  (push (quri:uri-query (quri:uri (cdr (assoc :uri (request-headers req))))) env)
	  (push :query-string env))
	;;TODO Fix mongrel2
	(push "" env)
	(push :server-name env)
	;;TODO Fix mongrel2
	(push 0 env)
	(push :server-port env)
	(push (cdr (assoc :version (request-headers req))) env)
	(push :server-protocol env)
	(push (cdr (assoc :uri (request-headers req))) env)
	(push :request-uri env)
	(let ((body (request-body req)))
	  (when (> (length body) 0)
	    (push (length body) env)
	    (push :content-length env)
	    (push (flexi-streams:make-in-memory-input-stream body
							     :transformer #'char-code) env)
	    (push :raw-body env)))
	(push (cdr (assoc :remote_addr (request-headers req))) env)
	(push :remote-addr env)
	;;TODO Fix mongrel2
	(push 0 env)
	(push :remote-port env)
	env))))



(defvar *http-status* (make-hash-table :test #'eql))

(macrolet ((def-http-status (code phrase)
             `(setf (gethash ,code *http-status*) ,phrase)))
  (def-http-status 100 "Continue")
  (def-http-status 101 "Switching Protocols")
  (def-http-status 200 "OK")
  (def-http-status 201 "Created")
  (def-http-status 202 "Accepted")
  (def-http-status 203 "Non-Authoritative Information")
  (def-http-status 204 "No Content")
  (def-http-status 205 "Reset Content")
  (def-http-status 206 "Partial Content")
  (def-http-status 207 "Multi-Status")
  (def-http-status 300 "Multiple Choices")
  (def-http-status 301 "Moved Permanently")
  (def-http-status 302 "Moved Temporarily")
  (def-http-status 303 "See Other")
  (def-http-status 304 "Not Modified")
  (def-http-status 305 "Use Proxy")
  (def-http-status 307 "Temporary Redirect")
  (def-http-status 400 "Bad Request")
  (def-http-status 401 "Authorization Required")
  (def-http-status 402 "Payment Required")
  (def-http-status 403 "Forbidden")
  (def-http-status 404 "Not Found")
  (def-http-status 405 "Method Not Allowed")
  (def-http-status 406 "Not Acceptable")
  (def-http-status 407 "Proxy Authentication Required")
  (def-http-status 408 "Request Time-out")
  (def-http-status 409 "Conflict")
  (def-http-status 410 "Gone")
  (def-http-status 411 "Length Required")
  (def-http-status 412 "Precondition Failed")
  (def-http-status 413 "Request Entity Too Large")
  (def-http-status 414 "Request-URI Too Large")
  (def-http-status 415 "Unsupported Media Type")
  (def-http-status 416 "Requested range not satisfiable")
  (def-http-status 417 "Expectation Failed")
  (def-http-status 424 "Failed Dependency")
  (def-http-status 500 "Internal Server Error")
  (def-http-status 501 "Not Implemented")
  (def-http-status 502 "Bad Gateway")
  (def-http-status 503 "Service Unavailable")
  (def-http-status 504 "Gateway Time-out")
  (def-http-status 505 "Version not supported"))

(defun http-status-reason (code)
  (gethash code *http-status*))
