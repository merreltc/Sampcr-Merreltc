;:  Single-file version of the interpreter.
;; Easier to submit to server, probably harder to use in the development process

(load "chez-init.ss") 

;-------------------+
;                   |
;    DATATYPES      |
;                   |
;-------------------+

(define (literal? var)
  (or (symbol? var)
      (boolean? var)
      (string? var)
      (number? var)
      (vector? var)
      (quoted? var)))

(define (literal-ext? var)
  (or (symbol? var)
      (boolean? var)
      (string? var)
      (number? var)
      (vector? (list 'quote var))
      (list? (list 'quote var))))

(define (quoted? var)
  (and (list? var)
       (eq? (1st var) 'quote)))

(define (improper? pair)
  (if (and (not (null? pair))
     (not (eq?   (cdr pair) '()))
     (not (pair? (cdr pair))))
      #t
      (if (null? (cdr pair))
    #f
    (improper? (cdr pair)))))

; parsed expression

(define-datatype expression expression?
  [var-exp
   (id symbol?)]
  [lambda-variable-exp
   (vars symbol?)
   (bodies (list-of expression?))]
  [lambda-improper-exp
   (vars (list-of symbol?))
   (bodies (list-of expression?))]
  [lambda-fixed-exp
   (vars (list-of symbol?))
   (bodies (list-of expression?))]
  [app-exp
   (rator expression?)
   (rands (list-of expression?))]
  [lit-exp
   (id literal-ext?)] ; Expand to include other variable types
  [if-exp
   (condition expression?)
   (if-true expression?)
   (if-false expression?)]
  [if-onlythen-exp
   (condition expression?)
   (if-true expression?)]
  [let-exp
   (vars (list-of symbol?))
   (exps (list-of expression?))
   (bodies (list-of expression?))]
  [let*-exp
   (varids (list-of symbol?))
   (varexps (list-of expression?))
   (bodies (list-of expression?))]
  [letrec-exp
   (varids (list-of symbol?))
   (varexps (list-of expression?))
   (bodies (list-of expression?))]
  [namedlet-exp
   (id symbol?)
   (varids (list-of symbol?))
   (varexps (list-of expression?))
   (bodies (list-of expression?))]
  [set!-exp
   (id symbol?)
   (exp expression?)])

	
	

;; environment type definitions

(define scheme-value?
  (lambda (x) #t))

(define-datatype environment environment?
  (empty-env-record)
  (extended-env-record
   (syms (list-of symbol?))
   (vals (list-of scheme-value?))
   (env environment?)))

; datatype for procedures.  At first there is only one
; kind of procedure, but more kinds will be added later.

(define-datatype proc-val proc-val?
  [prim-proc
   (name symbol?)]
  [closure (vars (list-of symbol?))
           (bodies (list-of expression?))
           (env environment?)])
	 
	

;-------------------+
;                   |
;    PARSER         |
;                   |
;-------------------+


; This is a parser for simple Scheme expressions, such as those in EOPL, 3.1 thru 3.3.

; You will want to replace this with your parser that includes more expression types, more options for these types, and error-checking.

; Procedures to make the parser a little bit saner.
(define 1st car)
(define 2nd cadr)
(define 3rd caddr)

(define parse-exp         
  (lambda (datum)
    (cond
     
     [(null? datum)
      '()]
     
     ;; variable expressions
     [(symbol? datum)
      (var-exp datum)]
     
     ;; literal expressions
     [(literal? datum)
      (cond 
       [(and (pair? datum) (improper? datum))
  (eopl:error 'parse-exp "expression ~s is not a proper list" datum)]
       [(quoted? datum) (lit-exp (2nd datum))]
       [else (lit-exp datum)])]
     
     ;; all "list" expressions
     [(pair? datum)
      (cond
       [(improper? datum)
  (eopl:error 'parse-exp "expression ~s is not a proper list" datum)]
       
       ;; lambda expressions
       [(eqv? (1st datum) 'lambda)
  (cond
   ;; Check for body
   [(<= (length datum) 2)
    (eopl:error 'parse-exp "lambda-expression: incorrect length ~s" datum)]
   
   ;; Check for non-symbols in arg list
   [(or (and (list? (2nd datum))
       (not (null? (2nd datum)))
       (not (andmap (lambda (n)
          (symbol? n))
        (2nd datum))))
        (not (or (list? (2nd datum))
           (symbol? (2nd datum)))))
    (eopl:error 'parse-exp "lambda's formal arguments ~s must all be symbols" datum)]

   ;; Correct types of lambdas
   [(symbol? (2nd datum))
    (lambda-variable-exp (2nd datum)
             (map parse-exp (cddr datum)))]
   [(and (not (null? (2nd datum))) (improper? (2nd datum)))
    (lambda-improper-exp (2nd datum)
             (map parse-exp (cddr datum)))]
   [else
    (lambda-fixed-exp (2nd datum)
          (map parse-exp (cddr datum)))])]
       
       ;; if expressions
       [(eqv? (1st datum) 'if)
  (cond
   ;; Check for body
   [(<= (length datum) 2)
    (eopl:error 'parse-exp "if-expression ~s does not have (only) test, then, and else" datum)]

   [(>= (length datum) 5)
    (eopl:error 'parse-exp  "if-expression has incorrect length ~s" datum)]
   
   [else
    (if (null? (cdddr datum))
        (if-onlythen-exp (parse-exp (2nd datum))
             (parse-exp (3rd datum)))
        (if-exp (parse-exp (2nd datum))
          (parse-exp (3rd datum))
          (parse-exp (3rd (cdr datum)))))])]
       
       ;; named-let expressions
       [(and (eqv? (1st datum) 'let) (symbol? (2nd datum)))
  (cond
   ;; declaration are a list
   [(not (list? (3rd datum)))
    (eopl:error 'parse-exp "declarations in ~s-expression not a list ~s" datum)]
     
   ;; improper declaration list
   [(and (not? (null? (3rd datum))) (improper? (3rd datum)))
    (eopl:error 'parse-exp "declarations in ~s-expression not a list ~s" datum)]
   
   ;; improper list in declaration
   [(and (not? (null? (3rd datum))) (ormap improper? (3rd datum)))
    (eopl:error 'parse-exp "declaration in ~s-exp is not a proper list ~s" datum)]

   ;; no body
   [(<= (length datum) 3)
    (eopl:error 'parse-exp  "~s-expression has incorrect length ~s" datum)]
   
   ;; All declarations are lists of length 2
   [(and (not (null? (3rd datum))) (not (andmap (lambda (declaration)
       (= (length declaration) 2))
           (3rd datum))))
    (eopl:error 'parse-exp "declaration in ~s-exp must be a list of length 2 ~s" datum)]
   
   ;; vars in declaration not symbols
   [(and (not (null? (3rd datum))) (not (andmap (lambda (declaration)
       (symbol? (car declaration)))
           (3rd datum))))
    (eopl:error 'parse-exp "vars in ~s-exp must be symbols ~s" datum)]
   
   [else
    (if (null? (3rd datum))
        (namedlet-exp (2nd datum)
          '()
          '()
          (map parse-exp (cdddr datum)))
        (namedlet-exp (2nd datum) (map 1st (3rd datum))
          (map parse-exp (map 2nd (3rd datum)))
          (map parse-exp (cdddr datum))))])]

       ;; let expressions
       [(eqv? (1st datum) 'let)
  (begin
    (check-let datum)
    (if (null? (2nd datum))
        (let-exp
         '()
         '()
         (map parse-exp (cddr datum)))
        (let-exp
         (map 1st (2nd datum))
         (map parse-exp (map 2nd (2nd datum)))
         (map parse-exp (cddr datum)))))]
  
       ;; let* expressions
       [(eqv? (1st datum) 'let*)
  (begin
    (check-let datum)
    (if (null? (2nd datum))
        (let*-exp
         '()
         '()
         (map parse-exp (cddr datum)))
        (let*-exp
         (map 1st (2nd datum))
         (map parse-exp (map 2nd (2nd datum)))
         (map parse-exp (cddr datum)))))]

       ;; letrec expressions
       [(eqv? (1st datum) 'letrec)
  (begin
    (check-let datum)
   (if (null? (2nd datum))
        (letrec-exp
         '()
         '()
         (map parse-exp (cddr datum)))
        (letrec-exp
         (map 1st (2nd datum))
         (map parse-exp (map 2nd (2nd datum)))
         (map parse-exp (cddr datum)))))]

       ;; set! expressions
       [(eqv? (1st datum) 'set!)
  (cond
   [(<= (length datum) 2)
    (eopl:error 'parse-exp "set! expression ~s does not have (only) variable and expression" datum)]
   [(>= (length datum) 4)
    (eopl:error 'parse-exp  "set! expression has incorrect length ~s" datum)]
   [else
    (set!-exp (2nd datum) (parse-exp (3rd datum)))])]

       ;; application expressions
       [else
  (cond
   [(null? (cdr datum))
    (app-exp (parse-exp (1st datum)) '())]
   [else
    (app-exp (parse-exp (1st datum))
         (map parse-exp (cdr datum)))])])]
     [else (eopl:error 'parse-exp "bad expression: ~s" datum)])))


(define (check-let exp)
  (cond
   ;; declaration are a list
   [(not (list? (2nd exp)))
    (eopl:error 'parse-exp "declarations in ~s-expression not a list ~s" exp)]
      
   ;; improper declaration list
   [(and (not (null? (2nd exp))) (improper? (2nd exp)))
    (eopl:error 'parse-exp "declarations in ~s-expression not a list ~s" exp)]
   
   ;; improper list in declaration
   [(and (not (null? (2nd exp))) (ormap improper? (2nd exp)))
    (eopl:error 'parse-exp "declaration in ~s-exp is not a proper list ~s" exp)]

   ;; no body
   [(<= (length exp) 2)
    (eopl:error 'parse-exp  "~s-expression has incorrect length ~s" exp)]
   
   ;; All declarations are lists of length 2
   [(and (not (null? (2nd exp))) (not (andmap (lambda (declaration)
       (= (length declaration) 2))
     (cadr exp))))
    (eopl:error 'parse-exp "declaration in ~s-exp must be a list of length 2 ~s" exp)]
   
   ;; vars in declaration not symbols
   [(and (not (null? (2nd exp))) (not (andmap (lambda (declaration)
       (symbol? (car declaration)))
     (2nd exp))))
    (eopl:error 'parse-exp "vars in ~s-exp must be symbols ~s" exp)]
   
   [else (void)]))








;-------------------+
;                   |
;   ENVIRONMENTS    |
;                   |
;-------------------+





; Environment definitions for CSSE 304 Scheme interpreter.  Based on EoPL section 2.3

(define empty-env
  (lambda ()
    (empty-env-record)))

(define extend-env
  (lambda (syms vals env)
    (extended-env-record syms vals env)))

(define list-find-position
  (lambda (sym los)
    (list-index (lambda (xsym) (eqv? sym xsym)) los)))

(define list-index
  (lambda (pred ls)
    (cond
     ((null? ls) #f)
     ((pred (car ls)) 0)
     (else (let ((list-index-r (list-index pred (cdr ls))))
	     (if (number? list-index-r)
		 (+ 1 list-index-r)
		 #f))))))

(define apply-env
  (lambda (env sym succeed fail) ; succeed and fail are procedures applied if the var is or isn't found, respectively.
    (cases environment env
      (empty-env-record ()
        (fail))
      (extended-env-record (syms vals env)
	(let ((pos (list-find-position sym syms)))
      	  (if (number? pos)
	      (succeed (list-ref vals pos))
	      (apply-env env sym succeed fail)))))))








;-----------------------+
;                       |
;   SYNTAX EXPANSION    |
;                       |
;-----------------------+



; To be added later









;-------------------+
;                   |
;   INTERPRETER    |
;                   |
;-------------------+



; top-level-eval evaluates a form in the global environment


(define top-level-eval
  (lambda (form)
    ; later we may add things that are not expressions.
    (eval-exp form (empty-env))))


(define eval-bodies
  (lambda (bodies env)
    (if (null? (cdr bodies))
      (eval-exp (car bodies) env)
      (begin
        (eval-exp (car bodies) env)
        (eval-bodies (cdr bodies) env)))))

; eval-exp is the main component of the interpreter

(define eval-exp
  (let ([identity-proc (lambda (x) x)])
    (lambda (exp env)
      (cases expression exp
        [lit-exp (datum) datum]
        [var-exp (id) ; look up its value.
          (apply-env env
                     id
                     identity-proc ; procedure to call if id is in env
          (lambda () ; procedure to call if id is not in env
          (apply-env global-env ; was init-env
                     id
                     identity-proc ; call if id is in global-env
                     (lambda () ; call if id not in global-env
                      (error 'apply-env
                        "variable ~s is not bound"
                        id)))))]
        [let-exp (vars exps bodies)
          (let ([new-env (extend-env vars 
                                     (eval-rands exps env) 
                                     env)])
                (eval-bodies bodies new-env))]
        [if-exp (test-exp then-exp else-exp)
          (if (eval-exp test-exp env)
            (eval-exp then-exp env)
            (eval-exp else-exp env))]
        [lambda-fixed-exp (vars bodies)
          (closure vars bodies env)]
        [app-exp (rator rands)
          (let ([proc-value (eval-exp rator env)]
                [args (eval-rands rands env)])
            (apply-proc proc-value args))]
        [else (error 'eval-exp
                "Bad abstract syntax: ~a" exp)]))))

; evaluate the list of operands, putting results into a list

(define eval-rands
  (lambda (rands env)
    (map (lambda (e)
          (eval-exp e env)) rands)))

;  Apply a procedure to its arguments.
;  At this point, we only have primitive procedures.  
;  User-defined procedures will be added later.

(define apply-proc
  (lambda (proc-value args)
    (cases proc-val proc-value
      [prim-proc (op) (apply-prim-proc op args)]
      [closure (vars bodies env)
        (eval-bodies bodies 
                     (extend-env vars args env))]
			; You will add other cases
      [else (eopl:error 'apply-proc
                   "Attempt to apply bad procedure: ~s" 
                    proc-value)])))

(define *prim-proc-names* '(+ - * / add1 sub1 cons = zero? not < >= <= > 
                            car cdr list null? eq? equal? length list->vector 
                            list? pair? procedure? vector->list vector? number? symbol?
                            caar cddr cadr cdar caaar caadr caddr cdddr cdaar cddar cadar cdadr
                            set-car! set-cdr!))

(define init-env         ; for now, our initial global environment only contains 
  (extend-env            ; procedure names.  Recall that an environment associates
     *prim-proc-names*   ;  a value (not an expression) with an identifier.
     (map prim-proc      
          *prim-proc-names*)
     (empty-env)))

(define global-env init-env)

; Usually an interpreter must define each 
; built-in procedure individually.  We are "cheating" a little bit.

(define apply-prim-proc
  (lambda (prim-proc args)
    (case prim-proc
      [(+) (apply + args)]
      [(-) (apply - args)]
      [(*) (apply * args)]
      [(/) (/ (1st args) (2nd args))]
      [(zero?) (zero? (1st args))]
      [(not) (not (1st args))]
      [(<) (< (1st args) (2nd args))]
      [(<=) (<= (1st args) (2nd args))]
      [(>) (> (1st args) (2nd args))]
      [(>=) (>= (1st args) (2nd args))]
      [(add1) (+ (1st args) 1)]
      [(sub1) (- (1st args) 1)]
      [(cons) (cons (1st args) (2nd args))]
      [(car) (car (1st args))]
      [(cdr) (cdr (1st args))]
      [(caar) (caar (1st args))]
      [(cddr) (cddr (1st args))]
      [(cadr) (cadr (1st args))]
      [(cdar) (cdar (1st args))]
      [(caaar) (caaar (1st args))]
      [(caadr) (caadr (1st args))]
      [(caddr) (caddr (1st args))]
      [(cdddr) (cdddr (1st args))]
      [(cdaar) (cdaar (1st args))]
      [(cddar) (cddar (1st args))]
      [(cadar) (cadar (1st args))]
      [(cdadr) (cdadr (1st args))]
      [(list) (apply list args)]
      [(null?) (null? (1st args))]
      [(assq) (apply assq args)]
      [(eq?) (eq? (1st args) (2nd args))]
      [(equal?) (equal? (1st args) (2nd args))]
      [(atom?) (display "didn't know we needed this!")]
      [(length) (length (1st args))]
      [(list->vector) (list->vector (1st args))]
      [(list?) (list? (1st args))]
      [(pair?) (pair? (1st args))]
      [(procedure?) (proc-val? (1st args))]
      [(vector->list) (vector->list (1st args))]
      [(vector) (display "didn't know we needed this!")]
      [(make-vector) (display "didn't know we needed this!")]
      [(vector-ref) (display "didn't know we needed this!")]
      [(vector?) (vector? (1st args))]
      [(number?) (number? (1st args))]
      [(symbol?) (symbol? (1st args))]
      [(set-car!) (set-car! (1st args) (2nd args))] 
      [(set-cdr!) (set-cdr! (1st args) (2nd args))] 
      [(vector-set!) (display "didn't know we needed this!")]
      [(display) (display "didn't know we needed this!")]
      [(newline) (display "didn't know we needed this!")]
      [(=) (= (1st args) (2nd args))]
      [else (error 'apply-prim-proc 
            "Bad primitive procedure name: ~s" 
            prim-proc)])))

(define rep      ; "read-eval-print" loop.
  (lambda ()
    (display "--> ")
    ;; notice that we don't save changes to the environment...
    (let ([answer (top-level-eval (parse-exp (read)))])
      ;; TODO: are there answers that should display differently?
      (eopl:pretty-print answer) (newline)
      (rep))))  ; tail-recursive, so stack doesn't grow.

(define eval-one-exp
  (lambda (x) (top-level-eval (parse-exp x))))