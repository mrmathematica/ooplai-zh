# 2 寻找 Self

在前一章中，我们构建了一个简单的对象系统。现在我们来考虑为点对象定义 above 方法
，它读入的参数是另一个点，返回更高的（从 y 轴角度看）点：

```Racket
(method above (other-point)
        (if (> (-> other-point y?) y)
            other-point
            self))
```

请注意，我们直观地使用 self 来表示当前正在执行的对象；在其他有些语言中，它被称为
this。显然，我们对 OOP 的描述并没有告诉我们 self 是什么。

## 2.1 Self 是什么?

回过头看看最初那个对象的定义（没有宏的那个）。对象是函数；所以我们想要的是在这个
函数范围内能够引用自己。该怎么做呢？研究递归的时候我们已经知道答案了！只需使用递
归绑定（letrec）给函数—对象命名，然后就可以在方法定义中使用了：

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

请注意，letrec 的主体就返回 self，它绑定到我们定义的递归子程序。

```Racket
> ((point 'x! 10) 'x?)
10
```

> 在 Smalltalk 语言中，方法默认返回 self。

请注意，赋值方法`x!`返回 self，这使得我们可以链式传递消息。

## 2.2 用宏实现 Self

在我们的 OBJECT 宏中使用上述模式：

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

什么？？我们明明用 letrec 定义了 self，为什么报错说它没有定义呢？原因是——**卫
生**！要知道 Scheme 的 syntax-rules 是卫生的，因此，它会透明地重命名宏引入的所有
标识符，以确保在宏展开后他们不会意外绑定或者被绑定。使用 DrRacket 的宏步进器
（macro stepper）可以很清楚地观察到这一点。你会看到，greater 方法中的 self 标识
符与 letrec 表达式中的同名标识符的颜色不同。

幸运的是，defmac 支持一种方法，指定宏本身引入的标识符也可以被用户代码使用。这里
我们唯一需要做的是指定 self 就是这样的标识符：

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

## 2.3 用到 Self 的点对象

现在我们可以定义种种方法，或返回 self，或在方法体中使用 self：

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

上一节已经表明，方法可以通过向 self 发送消息来使用其他方法。这个例子展示相互递归
的方法。

> 请在 Java 中尝试相同的定义，然后比较“大”数字的结果。是啊，我们的简单对象系统确
> 实从尾调用优化中受益了！

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

我们现在的对象系统支持 self，包括返回 self、发送消息给 self。请注意，方法中使用
的 self 是在对象创建时被绑定的：在方法被定义时，它们捕获对 self 的绑定，此后该绑
定就被固定了。我们将在下面的章节中看到，如果想要支持委托，或者想要支持类，这就行
不通了。

## 2.5 嵌套的对象

对象和方法最终被编译成 Scheme 中的 lambda，因此我们的对象继承了一些有趣的属性。
首先，正如我们所看到的，它们是一等公民（不然这一切还有意思吗？）。另外，正如我们
刚刚看到的，尾位置的方法调用被视为尾调用，因此空间没有浪费。接下来讨论另一个好处
：我们可以使用高阶的编程模式，比如产生对象的对象（通常称为**工厂**）。换一种说法
，运用合适的词法范围，我们可以定义**嵌套的对象**。

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

> 在 Java 中你能这么做吗？

请验证这些返回。
