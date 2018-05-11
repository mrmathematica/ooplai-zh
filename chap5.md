# 5 类

回头讨论工厂函数（参见[构造对象](./chap1.md#13-构造对象)）：

```Racket
(define (make-point init-x)
  (OBJECT
   ([field x init-x])
   ([method x? () x]
    [method x! (new-x) (begin (set! x new-x) self)])))
 
(define p1 (make-point 0))
(define p2 (make-point 1))
```

所有点对象都拥有自己的方法，尽管它们是相同的。至少它们的签名和主体是一样的，对吧？它们**完全**一样吗？事实并非如此。在这个版本的对象系统中，唯一的区别是，方法中包含对象自身：就是说，在p1的方法中，self指向p1，而在p2的方法中它指向p2。换句话说，方法，也就是函数，因所捕捉的词法环境而不同。

## 5.1 共享方法定义

为了支持不同的self，就重复所有的方法定义并不合理。将共同部分（方法体）分解出来，参数化于不同部分（绑定到self的对象）更合理。

先试试不用宏来实现。回想一下，不使用宏的情况下，点对象的定义如下：

```Racket
(define make-point
  (λ (init-x)
    (letrec ([self
              (let ([x init-x])
                (let ([methods (list (cons 'x? (λ () x))
                                     (cons 'x! (λ (nx)
                                                 (set! x nx)
                                                 self)))])
                  (λ (msg . args)
                    (apply (cdr (assoc msg methods)) args))))])
      self)))
```

如果将`(let ([methods...]))`从`(λ (init-x) ...)`中提取出来，我们就可以实现想要的方法定义的共享。但是，现在字段变量不在方法体的范围内了。具体地说，在这个例子中，这意味着x在两个方法中都没有绑定。这表明，除了self之外，方法还需要参数化于状态（字段值）之上。不过，好在self可以“持有”状态（它可以捕获其词法环境中的字段绑定）。只要通过self能够提取字段值（还有对其赋值）就可以了。为此，我们的对象将支持两个特定的消息`-read`和`-write`:

```Racket
(define make-point
  (let ([methods (list (cons 'x? (λ (self)
                                    (λ () (self '-read))))
                       (cons 'x! (λ (self)
                                    (λ (nx)
                                      (self '-write nx)
                                      self))))])
    (λ (init-x)
      (letrec ([self
                (let ([x init-x])
                  (λ (msg . args)
                    (case msg
                      [(-read) x]
                      [(-write) (set! x (first args))]
                      [else
                       (apply ((cdr (assoc msg methods)) self) args)])))])
      self))))
```

请仔细研究这里的方法现在是如何参数化于self的，还有，要存取字段现在需要向self发送特殊消息。接下来再研究对象本身的定义：当收到消息时，它首先检查消息是否为-read或-write，如果是的话就进行存取操作。来试试这是否可行：

```Racket
(define p1 (make-point 1))
(define p2 (make-point 2))

 
> ((p1 'x! 10) 'x?)
10
> (p2 'x?)
2
```

## 5.2 访问字段

当然，这个定义不怎么通用，因为它只适用于一个字段x。我们需要将其一般化：字段名必须作为参数传给-read和-write消息。问题是，如何用字段名（以符号的形式）在对象的词法环境中实际访问同名变量。一个简单的解决方案是使用某种结构来保存字段值。方法的定义就是这样处理的，保存的是方法名称和方法定义之间的关联。不过，与方法表不同，字段绑定是（至少是潜在）可变的。Racket不支持对关联表进行赋值，所以我们使用字典（更确切地说，哈希表），用`dict-ref`和`dict-set!`访问。

```Racket
(define make-point
  (let ([methods (list (cons 'x? (λ (self)
                                    (λ () (self '-read 'x))))
                       (cons 'x! (λ (self)
                                  (λ (nx)
                                    (self '-write 'x nx)
                                    self))))])
    (λ (init-x)
      (letrec ([self
                (let ([fields (make-hash (list (cons 'x init-x)))])
                  (λ (msg . args)
                    (case msg
                      [(-read)  (dict-ref  fields (first args))]
                      [(-write) (dict-set! fields (first args)
                                                  (second args))]
                      [else
                       (apply ((cdr (assoc msg methods)) self) args)])))])
      self))))

> (let ((p1 (make-point 1))
        (p2 (make-point 2)))
    (+ ((p1 'x! 10) 'x?)
       (p2 'x?)))
12
```

请注意make-point现在保存了方法定义的列表，还有，被创建的对象捕获了fields(字段)字典（该字典先初始化，然后返回给对象）。

## 5.3 类

虽然我们的确实现了方法定义的共享，但是这个解决方案并不理想。为什么？观察对象的定义（上述`(λ (msg . args) ....)`的函数体）。在那里实现的逻辑在所有用make-point创建对象中都是重复的：每个对象都有它自己的副本，当它收到-read消息时，在fields字典中查找；-write 消息时，更新fields字典；任何其他消息，查找methods表，然后应用对应方法。

所以说，所有这些逻辑在对象之间都可以共享。对象体中唯一的自由变量是fields和self。换句话说，我们可以把对象定义为它自己外加它的字段，而把所有其他的逻辑都交给make-point函数。这样的话，make-point的功能不再是单一的只负责创建新的对象，还负责处理对字段的访问和对消息的处理。也就是说，make-point演变成所谓的**类**（class）。

我们如何表示类？目前它只是可以调用的函数（它会创建对象——一个**实例**）；如果需要该函数有不同的行为，我们可以应用本书开始时看到的[对象模式](.chap1.md#11-有状态函数与对象模式)。

> 在某些语言中，类本身就是对象。这方面的范例就是Smalltalk。绝对值得花时间一学！

于是：

```Racket
(define Point
  ....
  (λ (msg . args)
    (case msg
      [(create) create instance]
      [(read) read field]
      [(write) write field]
      [(invoke) invoke method])))
```

这种模式明确了类的作用：它产生对象，调用方法，读取和写入其实例的字段。

现在，对象的作用是什么？他只需要有标识（identity）功能，知道自己属于哪个类，并记录自己的字段值。它不再自带任何行为。换种说法，对象可以定义为普通的数据结构：

```Racket
(define-struct obj (class values))
```

接下来看看现在该怎么定义Point类：

```Racket
(define Point
  (let ([methods ....])
    (letrec
        ([class
             (λ (msg . vals)
               (case msg
                 [(create) (let ((values (make-hash '((x . 0)))))
                             (make-obj class values))]
                 [(read) (dict-ref (obj-values (first vals))
                                   (second vals))]
                 [(write) (dict-set! (obj-values (first vals))
                                     (second vals)
                                     (third vals))]
                 [(invoke)
                   (let ((found (assoc (second vals) methods)))
                     (if found
                         (apply ((cdr found) (first vals)) (cddr vals))
                         (error "message not understood")))]))])
      class)))

> (Point 'create)
#<obj>
```

要实例化Point类，只需向其发送create消息。现在对象是结构体了，我们需要一种方法来发送消息，还有访问其字段。要向对象p发送消息，先要检索它的类，然后给这个类发送invoke消息：

```Racket
((obj-class p) 'invoke p 'x?)
```

访问字段也是类似。

## 5.4 在Scheme中嵌入类

本节我们使用宏在Scheme中嵌入类。

### 5.4.1 类的宏

我们来定义CLASS语法抽象，它负责创建类：

```Racket
(defmac (CLASS ([field f init] ...)
               ([method m params body] ...))
     #:keywords field method
     #:captures self
     (let ([methods (list (cons 'm (λ (self)
                                     (λ params body))) ...)])
       (letrec
           ([class
                (λ (msg . vals)
                  (case msg
                    [(create)
                     (make-obj class
                               (make-hash (list (cons 'f init) ...)))]
                    [(read)
                     (dict-ref (obj-values (first vals)) (second vals))]
                    [(write)
                     (dict-set! (obj-values (first vals)) (second vals) (third vals))]
                    [(invoke)
                     (if (assoc (second vals) methods)
                         (apply ((cdr (assoc (second vals) methods)) (first vals)) (cddr vals))
                         (error "message not understood"))]))])
         class)))
```

### 5.4.2 辅助语法

我们需要引入新的语法定义，以方便地调用方法（`->`），还需要引入类似的语法，来访问当前对象的字段（`?`和`!`）。

```Racket
(defmac (-> o m arg ...)
  (let ((obj o))
    ((obj-class obj) 'invoke obj 'm arg ...)))

(defmac (? fd) #:captures self
  ((obj-class self) 'read self 'fd))
 
(defmac (! fd v) #:captures self
  ((obj-class self) 'write self 'fd v))
```

还可以定义辅助函数来创建新的实例：

```Racket
(define (new c)
  (c 'create))
```

这个简单的函数在概念上非常重要：它有助于隐藏类在内部作为函数实现的事实，还隐藏了用于请求类创建实例的符号。

### 5.4.3 例子

来看类的例子：

```Racket
(define Point
 (CLASS ([field x 0])
        ([method x? () (? x)]
         [method x! (new-x) (! x new-x)]
         [method move (n) (-> self x! (+ (-> self x?) n))])))
 
(define p1 (new Point))
(define p2 (new Point))

 
> (-> p1 move 10)
> (-> p1 x?)
10
> (-> p2 x?)
0
```

### 5.4.4 强封装

关于字段访问，我们做了个重要的设计决定：字段访问器`?`和`!`只能作用于self！即，在我们的语言中不可能访问另一个对象的字段。这被称为具有**强封装**（Strong Encapsulation）对象的语言。Smalltalk就是这样（访问另一个对象的字段实际上是发送消息，因此可以由接收方对象来控制）。Java不是：可以访问任何对象的字段（如果可见性(visibility)允许的话）。我们的**语法**根本不允许访问外部字段。

这样设计的另一个结果是，字段访问只能出现在方法体**内**：因为接收对象总是self，所以self必须已定义。比如说，试试在对象之外用`?`读取字段：

```Racket
> (? f)
self: undefined;
 cannot reference undefined identifier
```

更好的做法是，上述程序会产生错误，表明`?`未定义。要做到这一点，我们简单地将`?`和`?`定义为**局部**语法形式，只在方法体的内被定义，而不是全局范围内有定义。只要将这些字段访问形式的定义从全局移动到local的作用域内，local放在方法定义内：

```Racket
(defmac (CLASS ([field f init] ...)
               ([method m params body] ...))
     #:keywords field method
     #:captures self ? !
     (let ([methods
            (local [(defmac (? fd) #:captures self
                      ((obj-class self) 'read self 'fd))
                    (defmac (! fd v) #:captures self
                      ((obj-class self) 'write self 'fd v))]
              (list (cons 'm (λ (self)
                               (λ params body))) ...))])
                (letrec
                   ([class (λ (msg . vals) ....)]))))
```

在方法列表定义的局部范围内定义语法形式`?`和`!`，确保了它们可以在方法体内可用，但在其他地方不可用。

现在，字段访问器方法之外没有定义：

```Racket
> (? f)
?: undefined;
 cannot reference undefined identifier
```

后文统一使用这种局部的方法。

## 5.5 初始化

我们已经看到，要从类获取对象（即实例化对象）的方法是向类发送create消息。能够给create传递参数，以指定对象的字段的初始值通常是有用的。目前，我们的类系统仅支持在类声明时指定默认字段值。在实例化时间没法传递初始字段值。

> 初始化方法是Smalltalk编程中的习惯叫法。在Java中，它们被称为构造函数（这可以说是个糟糕的名字，因为我们可以看到，它们并不负责构建对象，只是在实际创建对象之后才对其进行初始化）。

有几种方法可以做到这一点。一个简单的方法是，要求对象实现**初始化**方法，并让这个类在每个新创建的对象上调用此初始化方法。我们将采用如下约定：如果create消息没有参数，那么我们不调用初始器（因此使用默认值）。如果有参数传入，我们就用这些参数调用初始器（称之为initialize）：

```Racket
....
(λ (msg . vals)
  (case msg
    [(create)
     (if (null? vals)
         (make-obj class
                   (make-hash (list (cons 'f init) ...)))
         (let ((object (make-obj class (make-hash))))
           (apply ((cdr (assoc 'initialize methods)) object) vals)
           object))]
    ....)) ....
```

我们可以改进实例化类的辅助函数，使其接受可变数目的参数：

```Racket
(define (new class . init-vals)
    (apply class 'create init-vals))
```

来试试看：

```Racket
(define Point
 (CLASS ([field x 0])
        ([method initialize (nx) (-> self x! nx)]
         [method x? () (? x)]
         [method x! (nx) (! x nx)]
         [method move (n) (-> self x! (+ (-> self x?) n))])))
 
(define p (new Point 5))

> (-> p move 10)
> (-> p x?)
15
```

## 5.6 匿名类，局部类和嵌套类

我们扩展了Scheme，引入了类。扩展的方式类似于之前的对象系统，类表示为一等（first-class）函数。这意味着，我们语言中的类是一等的实体，例如可以作为参数传递（参见前面create函数的定义）。另外，我们的系统也支持匿名类和嵌套的类。当然，这一切都建立在遵从词法作用域规则的基础上。

```Racket
(define (cst-class-factory cst)
 (CLASS () ([method add (n) (+ n cst)]
            [method sub (n) (- n cst)]
            [method mul (n) (* n cst)])))
 
(define Ops10  (cst-class-factory 10))
(define Ops100 (cst-class-factory 100))

> (-> (new Ops10) add 10)
20
> (-> (new Ops100) mul 2)
200
```

我们也可以在局部范围内引入类。也就是说，不同于类是全局可见的一阶实体的语言，我们可以在局部定义类。

```Racket
(define doubleton
  (let ([the-class (CLASS ([field x 0])
                          ([method initialize (x) (-> self x! x)]
                           [method x? () (? x)]
                           [method x! (new-x) (! x new-x)]))])
    (let ([obj1 (new the-class 1)]
          [obj2 (new the-class 2)])
      (cons obj1 obj2))))

> (-> (cdr doubleton) x?)
2
```

在这里，引入the-class的的目的仅在于创建两个实例，然后以对的形式返回这两个实例。在那之后，这个类就不再可用了。换种说法，无法再创建这个类的更多实例了。不过，我们创建的这两个实例当然仍然指向它们的类，因此这些对象仍可以使用。有趣的是，一旦这些对象被垃圾收集，他们的类也可以被收回。
