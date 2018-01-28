# 2 寻找Self

在前一章中，我们构建了一个简单的对象系统。现在我们来考虑定义点对象的above方法，它读入的参数另一个点，返回更高（从y轴角度）的点：

```Racket
(method above (other-point)
        (if (> (-> other-point y?) y)
            other-point
            self))
```

请注意，我们直观地使用self来表示当前正在执行的对象；在其他有些语言中，它被称为this。显然，我们对OOP的描述并没有告诉我们self是什么。

## 2.1 Self是什么?

回过头看看最初那个对象的定义（没有宏的那个）。对象是函数；所以我们想要的是在这个函数范围内能够引用自己。该怎么做呢？研究递归的时候我们已经知道答案了！只需使用递归绑定（letrec）给函数-对象命名，然后就可以在方法定义中使用了：

```Racket
(define point
  (letrec ([self
            (let ([x 0])
              (let ([methods (list (cons 'x?  (λ () x))
                                   (cons 'x! (λ (nx)
                                               (set! x nx)
                                               self)))])
                (λ (msg . args)
                  (apply (cdr (assoc msg methods)) args))))])
    self))
```

请注意，letrec的主体就返回self，它绑定到我们定义的递归子程序。

```Racket
> ((point 'x! 10) 'x?)
10
```

> 在Smalltalk语言中，方法默认返回self。

请注意，赋值方法`x!`返回self，这使得我们可以链式传递消息。

## 2.2 用宏实现Self

在我们的OBJECT宏中使用上述模式：

```Racket
(defmac (OBJECT ([field fname init] ...)
                ([method mname args body] ...))
  #:keywords field method
  (letrec ([self
            (let ([fname init] ...)
              (let ([methods (list (cons 'mname (λ args body)) ...)])
                (λ (msg . vals)
                  (apply (cdr (assoc msg methods)) vals))))])
    self))
 
(defmac (-> o m arg ...)
  (o 'm arg ...))
```

用一些点对象试试：

```Racket
(define (make-point init-x)
  (OBJECT
   ([field x init-x])
   ([method x? () x]
    [method x! (nx) (set! x nx)]
    [method greater (other-point)
            (if (> (-> other-point x?) x)
                other-point
                self)])))
 
> (let ([p1 (make-point 5)]
        [p2 (make-point 2)])
    (-> p1 greater p2))
self: undefined;
 cannot reference undefined identifier
```

什么？？我们明明用letrec定义了self，为什么报错说它没有定义呢？原因是——**卫生**！要知道Scheme的syntax-rules是卫生的，因此，它会透明地重命名宏引入的所有标识符，以确保在宏展开后他们不会意外绑定或者被绑定。使用DrRacket的宏步进器（macro stepper）可以很清楚地观察到这一点。你会看到，greater方法中的self标识符与letrec表达式中的同名标识符的颜色不同。

幸运的是，defmac支持一种方法，指定宏本身引入的标识符也可以被用户代码使用。这里我们唯一需要做的是指定self就是这样的标识符：

```Racket
(defmac (OBJECT ([field fname init] ...)
                ([method mname args body] ...))
  #:keywords field method
  #:captures self
  (letrec ([self
            (let ([fname init] ...)
              (let ([methods (list (cons 'mname (λ args body)) ...)])
                (λ (msg . vals)
                  (apply (cdr (assoc msg methods)) vals))))])
    self))
```

## 2.3 用到Self的点对象

现在我们可以定义种种方法，或返回self，或在方法体中使用self：

```Racket
(define (make-point init-x init-y)
 (OBJECT
  ([field x init-x]
   [field y init-y])
  ([method x? () x]
   [method y? () y]
   [method x! (new-x) (set! x new-x)]
   [method y! (new-y) (set! y new-y)]
   [method above (other-point)
           (if (> (-> other-point y?) y)
               other-point
               self)]
 
   [method move (dx dy)
           (begin (-> self x! (+ dx (-> self x?)))
                  (-> self y! (+ dy (-> self y?)))
                  self)])))
 
(define p1 (make-point 5 5))
(define p2 (make-point 2 2))
 
> (-> (-> p1 above p2) x?)
5
> (-> (-> p1 move 1 1) x?)
6
```

## 2.4 互相递归的方法

上一节已经表明，方法可以通过向self发送消息来使用其他方法。这个例子展示相互递归的方法。

> 请在Java中尝试相同的定义，然后比较“大”数字的结果。是啊，我们的简单对象系统享受到了尾调用优化的好处！

```Racket
(define odd-even
  (OBJECT ()
   ([method even (n)
            (case n
              [(0) #t]
              [(1) #f]
              [else (-> self odd (- n 1))])]
    [method odd (n)
            (case n
              [(0) #f]
              [(1) #t]
              [else (-> self even (- n 1))])])))

 
> (-> odd-even odd 15)
#t
> (-> odd-even odd 14)
#f
> (-> odd-even even 14)
#t
```

我们现在的对象系统支持self，包括返回self、发送消息给self。请注意，self是在创建对象的时候绑定在方法中的：在方法被定义时，它们捕获对self的绑定，此后该绑定就被固定了。我们将在下面的章节中看到，如果想要支持委托，或者想要支持类，这就行不通了。

## 2.5 嵌套的对象

我们将对象和方法编译成Scheme中的lambda，所以他们继承了有趣的属性。首先，正如我们所看到的，它们是一等公民（不然这一切还有意思吗？）。另外，正如我们刚刚看到的，尾位置的方法调用被视为尾调用，因此空间没有浪费。接下来讨论另一个好处：我们可以使用高阶的编程模式，比如产生对象的对象（通常称为**工厂**）。换一种说法，运用合适的词法范围，我们可以定义**嵌套的对象**。

考虑如下的例子：

```Racket
(define factory
  (OBJECT
   ([field factor 1]
    [field price 10])
   ([method factor! (nf) (set! factor nf)]
    [method price! (np) (set! price np)]
    [method make ()
            (OBJECT ([field price price])
                    ([method val () (* price factor)]))])))

> (define o1 (-> factory make))
> (-> o1 val)
10
> (-> factory factor! 2)
> (-> o1 val)
20
> (-> factory price! 20)
> (-> o1 val)
20
> (define o2 (-> factory make))
> (-> o2 val)
40
```

> 在Java中你能这么做吗？

请验证这些返回。
