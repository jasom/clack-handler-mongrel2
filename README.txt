Clack backend for mongrel2

Note: this will ignore the port keyword option.  Instead use the sub-addr and
pub-addr keyword options.  e.g.:

 :sub-addr "tcp://127.0.0.1:9997"
 :pub-addr "tcp://127.0.0.1:9996"

Other options of note are :worker-entry and :worker-exit which will be called
upon thread-startup and exit for each worker thread.  This is useful for e.g.
ensuring each worker thread gets a long-lived database connection.
