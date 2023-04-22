#lang racket

;; defmac类似于define-syntax-rule，不过它还额外支持两种可选参数。
;; #:keywords <id> ... 指定生成宏的keywords
;; #:captures <id> ... 指定非卫生插入的名称
;; OOPLAI（http://www.dcc.uchile.cl/etanter/ooplai）全书使用defmac。

;; 直接受Eli Barzilay的http://tmp.barzilay.org/defmac.ss启发
;; （此版本只是对Eli的代码的重写，稍微调整了语法，并使用syntax-parse来处理可选参数）


(require (for-syntax syntax/parse))

(provide (all-defined-out))

(define-syntax (defmac stx)
  (syntax-parse stx
    [(defmac (name:identifier . xs) 
       (~optional (~seq #:keywords key:identifier ...) #:defaults ([(key 1) '()]))
       (~optional (~seq #:captures cap:identifier ...) #:defaults ([(cap 1) '()]))
       body:expr)
     #'(define-syntax (name stx)
         (syntax-case stx (key ...)
           [(name . xs)
            (with-syntax ([cap (datum->syntax stx 'cap stx)] ...)
              (syntax body))]))]))