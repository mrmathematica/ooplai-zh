# 1 从函数到简单对象

要探索面向对象编程语言，我们从PLAI（[《编程语言：应用和解释》](https://www.gitbook.com/read/book/lotuc/plai-cn)）中已经知道的，以及对于什么是对象的直觉开始。

## 1.1 有状态函数与对象模式

对象的目的是，将状态（可能但不一定是可变的）连同依赖于该状态的行为一起封装在一致的整体中。这里的状态通常被称为**字段**(field)（或**实例变量**(instance variable)），而行为是以**方法**(method)的形式提供。调用方法通常被称为**消息传递**(message passing)：发送消息给对象，如果它理解了，就执行相关的方法。

在Scheme这样的高级程序语言中，我们看到过类似的东西：

```Racket
(define add
  (λ (n)
    (λ (m)
      (+ m n))))

> (define add2 (add 2))
> (add2 5)
7
```

函数add2封装了隐藏状态（`n = 2`），其行为也依赖于该状态。所以从某种意义上说，闭包是一种对象，他的字段是（函数体中的）**自由变量**。那么其行为呢？好吧，闭包只有一个行为，通过函数**调用**触发（从消息传递的角度来看，apply(调用)是函数能理解的唯一消息）。

如果语言支持赋值（`set!`），那么我们就得到了有状态的函数，可以改变状态：

```Racket
(define counter
  (let ([count 0])
    (λ ()
      (begin
        (set! count (add1 count))
        count))))
```

现在我们可以观察到count状态的变化：

```Racket
> (counter)
1
> (counter)
2
```

现在，如果我们想要双向计数器呢？该函数必须能够在其状态上执行+1或者-1，取决于……好吧，参数！

```Racket
(define counter
  (let ([count 0])
    (λ (cmd)
      (case cmd
        [(dec) (begin
                 (set! count (sub1 count))
                 count)]
        [(inc) (begin
                 (set! count (add1 count))
                 count)]))))
```

请注意counter如何使用cmd来区分要执行的操作。

```Racket
> (counter 'inc)
1
> (counter 'dec)
0
```

这看起来很像有两个方法和一个实例变量的对象，不是吗？ 我们再来看一个例子，堆栈。

```Racket
(define stack
  (let ([vals '()])
    (define (pop)
      (if (empty? vals)
          (error "cannot pop from an empty stack")
          (let ([val (car vals)])
            (set! vals (cdr vals))
            val)))
 
    (define (push val)
      (set! vals (cons val vals)))
 
    (define (peek)
      (if (empty? vals)
          (error "cannot peek from an empty stack")
          (car vals)))
 
    (λ (cmd . args)
      (case cmd
        [(pop) (pop)]
        [(push) (push (car args))]
        [(peek) (peek)]
        [else (error "invalid command")]))))
```

这里，我们没有直接在lambda中编写方法体，而是使用了内层的define。另外请注意，我们在lambda的参数中使用了点符号：这样函数就能够接收第一个参数（cmd）以及此后零或多个的参数（作为列表在body中绑定到args）。

试试看：

```Racket
> (stack 'push 1)
> (stack 'push 2)
> (stack 'pop)
2
> (stack 'peek)
1
> (stack 'pop)
1
> (stack 'pop)
cannot pop from an empty stack
```

这代码的模式已经很明显了，可以用来定义类似于对象的抽象。更明确地抽象此模式：

```Racket
(define point
  (let ([x 0])
    (let ([methods (list (cons 'x? (λ () x))
                         (cons 'x! (λ (nx) (set! x nx))))])
    (λ (msg . args)
      (apply (cdr (assoc msg methods)) args)))))
```

请注意这里定义的λ，它以一种通用的方式分配正确的方法。我们首先把所有的方法都放在一个关联列表（即列表的元素都是对）中，将符号（也就是消息）关联到相应的方法。当调用point时，我们（用assoc）查找消息，得到相应的方法。然后我们调用方法。

```Racket
> (point 'x! 6)
> (point 'x?)
6
```

## 1.2 Scheme中的（第一种）简单对象系统

遵循上面确定的模式，我们可以用宏表达一个简单的对象系统。

> 请注意，在本书中我们使用[defmac](./defmac.rkt)来定义宏。defmac类似于define-syntax-rule，但是它还支持关键字参数，还有标识符的捕获（通过`#:keywords`和`#:captures`可选参数）。

```Racket
(defmac (OBJECT ([field fname init] ...)
                ([method mname args body] ...))
  #:keywords field method
  (let ([fname init] ...)
    (let ([methods (list (cons 'mname (λ args body)) ...)])
      (λ (msg . vals)
        (apply (cdr (assoc msg methods)) vals)))))
```

我们还可以定义箭头`->`符号表示定义发送消息给对象，例如`(-> st push 3)`：

```Racket
(defmac (-> o m arg ...)
  (o 'm arg ...))
```

现在就可以使用这个对象系统来定义二维点对象了：

```Racket
(define p2D
  (OBJECT
   ([field x 0]
    [field y 0])
   ([method x? () x]
    [method y? () y]
    [method x! (nx) (set! x nx)]
    [method y! (ny) (set! y ny)])))
```

这么使用：

```Racket
> (-> p2D x! 15)
> (-> p2D y! 20)
> (-> p2D x?)
15
> (-> p2D y?)
20
```

## 1.3 构造对象

到目前为止，我们所创建的对象都是独特的。如果我们想要多个点对象，每个可以有不同的初始坐标呢？

在函数式编程的语境中，我们知道如何正确地创建各种类似的函数：使用高阶函数，带上合适的参数，其作用是返回我们想要的特定实例。例如，从前面定义的add函数中，我们可以获得各种单参数加法函数：

```Racket
> (define add4 (add 4))
> (define add5 (add 5))
> (add4 1)
5
> (add5 1)
6
```

因为我们的简单对象系统根植于Scheme，所以可以简单地使用高阶函数来定义**对象工厂**（object factory）：

> JavaScript，AmbientTalk

```Racket
(define (make-point init-x init-y)
  (OBJECT
   ([field x init-x]
    [field y init-y])
   ([method x? () x]
    [method y? () y]
    [method x! (new-x) (set! x new-x)]
    [method y! (new-y) (set! y new-y)])))
```

make-point函数的参数是初始坐标，返回新创建的、正确地初始化后的对象。

```Racket
> (let ([p1 (make-point 5 5)]
        [p2 (make-point 10 10)])
    (-> p1 x! (-> p2 x?))
    (-> p1 x?))

10
```

## 1.4 动态分发

我们的简单对象系统就可以展示面向对象编程的基本特性：动态分发。请注意，在下面的代码中，node（节点）将sum消息发送给每个子节点，并不知道它们是leaf（叶节点）还是node：

```Racket
(define (make-node l r)
 (OBJECT
  ([field left l]
   [field right r])
  ([method sum () (+ (-> left sum) (-> right sum))])))
 
(define (make-leaf v)
 (OBJECT
  ([field value v])
  ([method sum () value])))

 
> (let ([tree (make-node
               (make-node (make-leaf 3)
                          (make-node (make-leaf 10)
                                     (make-leaf 4)))
               (make-leaf 1))])
   (-> tree sum))

18
```

尽管看起来很简单，这个对象系统已经足以说明对象的基本抽象机制，以及它和抽象数据类型（abstract data type）的区别。参见[第三章](./chap3.md)。

## 1.5 例外处理

让我们看看，如果发送消息给不知道如何处理它的对象会发生什么：

```Racket
> (let ([l (make-leaf 2)])
    (-> l print))
cdr: contract violation
  expected: pair?
  given: #f
```

这个错误信息很糟糕——它将我们的实现策略暴露给程序员，而且没有提示问题在哪。

我们可以改变OBJECT语法抽象的定义，正确地处理未知消息：

```Racket
(defmac (OBJECT ([field fname init] ...)
                ([method mname args body] ...))
  #:keywords field method
  (let ([fname init] ...)
    (let ([methods (list (cons 'mname (λ args body)) ...)])
      (λ (msg . vals)
        (let ([found (assoc msg methods)])
          (if found
              (apply (cdr found) vals)
              (error "message not understood:" msg)))))))
```

我们不再假设在对象的方法表中会有消息关联的方法，而是首先查找并将结果绑定到found；如果找不到方法，found将会是#f。在这种情况下，我们给出有意义的错误信息。

确实好多了：

```Racket
> (let ([l (make-leaf 2)])
    (-> l print))
message not understood: print
```

本章，我们成功地在Scheme中嵌入了一个简单的对象系统，它显示了词法作用域的一等函数和对象之间的连接。但是，我们还远没有完成，目前的对象系统仍然是原始和不完整的。
