# 4 转发和委托

通过消息发送的方式，如果一个对象不知道如何处理某条消息，总是可以将其转发给另一个对象。在我们的简单对象系统中，可以这么做：

```Racket
(define seller
 (OBJECT ()
  ([method price (prod)
           (* (case prod
                ((1) (-> self price1))
                ((2) (-> self price2)))
              (-> self unit))]
   [method price1 () 100]
   [method price2 () 200]
   [method unit () 1])))
 
(define broker
 (OBJECT
  ([field provider seller])
  ([method price (prod) (-> provider price prod)])))

> (-> broker price 2)
200
```

对象broker(中间商)不知道如何计算产品(prod，product)的价格，但是它可以提供price(价格)方法，其实现是简单地将消息转发给seller(卖方)，由seller实现所需的行为。请注意，broker在其provider(供应商)字段中保有对seller的引用。这是典型的对象组合的例子，由消息转发实现。

现在我们可以看到这种方法的问题了：消息的转发必须明文给出，对于每种我们预计可能发送给broker的消息，都必须定义一个方法，负责其转发。例如：

```Racket
> (-> broker unit)
message not understood: unit
```

## 4.1 消息转发

我们可以做得更好，让每个对象都有一个特殊的“伙伴”对象，任何不理解的消息都自动转发给它。要来构造这样的对象，我们可以定义新的语法抽象OBJECT-FWD：

```Racket
(defmac (OBJECT-FWD target
                    ([field fname init] ...)
                    ([method mname args body] ...))
  #:keywords field method
  #:captures self
  (letrec ([self
            (let ([fname init] ...)
              (let ([methods (list (cons 'mname (λ args body)) ...)])
                (λ (msg . vals)
                  (let ([found (assoc msg methods)])
                    (if found
                        (apply (cdr found) vals)
                        (apply target msg vals))))))])
    self))
```

请注意这里语法的扩展，指定了target对象；只要某条消息在对象的方法中找不到，调度过程就会使用target对象。当然，如果所有对象都将未知消息转发给其他对象，那么传递链中必须有个最后的对象，该对象在收到消息时可以简单报错：

```Racket
(define root
  (λ (msg . args)
    (error "not understood" msg)))
```

于是broker可以这样定义：

```Racket
(define broker
  (OBJECT-FWD seller () ()))
```

这就是说，broker是个空对象（不含字段，不含方法），只是将所有发送给它的消息转发给seller：

```Racket
> (-> broker price 2)
200
> (-> broker unit)
1
```

这种对象通常被称为**代理**（proxy）。

## 4.2 委托

假设我们想用broker来**改善**seller的行为；比方说，我们希望通过改变价格计算中使用的单位，来使每个产品的价格加倍。这很简单：我们只需要在broker中定义方法unit(单位)：

```Racket
(define broker
  (OBJECT-FWD seller ()
   ([method unit () 2])))
```

有了这个定义，我们应该确保向broker询问某个产品的价格是向seller询问同样产品价格的两倍：

```Racket
> (-> broker price 1)
100
```

嗯……这样不行！看来，一旦我们把price消息转发给seller，broker就再也不能进行控制了；特别地，seller发给self的unit消息**不会**被broker收到。

让我们考虑一下这是为什么。在seller中self绑定到哪个对象？seller！请记住，我们之前说过（参见[寻找Self](./chap2.md)），在我们的方法中，self是**静态绑定**的：当对象被创建时，self指向正被定义的对象/闭包，并且将始终绑定该值。这是因为letrec和let一样，遵从词法作用域。

我们正在寻找的则是另一种语义，称为**委托**（delegation）。委托要求对象中的self**动态绑定**：它应该始终指向最初接收消息的对象。在我们的例子中，这将确保当seller向self发送unit消息时，self指向broker，因此broker中新定义的unit会生效。在这种情况下，我们说seller是broker的**父对象**（parent），broker委托父对象处理消息。

怎样绑定标识符，能使其指向使用位置的值，而不是定义位置？在语音不提供动态作用域绑定指令的情况下，唯一可以实现这一点的方法是将该值作为参数传递。所以，必须给方法增加参数，新参数指向实际的接收方(receiver)。因此，self不再从词法作用域的环境中获取，而是通过参数获得。

具体说来，这意味着seller中这个方法：

```Racket
(λ (prod) .... (-> self unit) ....)
```

必须改为：

> 有没有想过为什么Python中的方法必须显式地接受self作为第一个参数？

```Racket
(λ (self)
  (λ (prod)....(-> self unit)....))
```

这个新参数有效地允许我们在查找得到方法后传递当前的接收方。

现在让我们定义新的语法形式OBJECT-DEL，来支持对象之间的委托（delegation）语义：

```Racket
(defmac (OBJECT-DEL parent
                    ([field fname init] ...)
                    ([method mname args body] ...))
  #:keywords field method
  #:captures self
  (let ([fname init] ...)
    (let ([methods
           (list (cons 'mname
                       (λ (self) (λ args body))) ...)])
      (λ (current)
        (λ (msg . vals)
          (let ([found (assoc msg methods)])
            (if found
                (apply ((cdr found) current) vals)
                (apply (parent current) msg vals))))))))
```

有几地方改动了：首先，target更名为parent，以明确我们定义的是委托语义。其次，如上所述，所有的方法现在都是带上了self参数。请注意，我们完全摆脱了letrec！这是因为letrec本来的用途就是允许对象引用self，同时遵循词法作用域。我们已经看到，对于委托来说，我们并不想要词法作用域。

这意味着，当我们在方法字典中找到某个方法时，必须首先将实际的接收方作为参数传给它。我们如何获得接收方？唯一的可能就是，给对象也加上参数，新参数是调用其方法时必须使用的当前接收方。也就是说，对象构造器返回的值不再是“`λ (msg . vals) ....`”，而是“`λ (rcvr) ....`”。“当前接收方”是我们的对象的参数。同样，如果某个消息不能被给定的对象所理解，那么它必须把当前接收者一起发送给它的父对象。

这样我们还有最后一个问题要解决：如何向对象发送消息？回忆一下，`->`的定义是：

```Racket
(defmac (-> o m arg ...)
  (o 'm arg ...))
```

但是现在我们不能简单地把o当做函数来调用，传给它一个符号（消息）和可变数量的参数。现在，对象是形式为`(λ (rcvr) (λ (msg . args) ....))`的函数。所以在传递消息和参数之前，我们必须指定哪个对象是当前的接收方。好吧，这很容易，因为在我们发送消息的时候，当前的接收方应该是……接受消息的对象！

> 为什么这里需要let绑定？

```Racket
(defmac (-> o m arg ...)
  (let ([obj o])
    ((obj obj) 'm arg ...)))
```

来看委托——也就是self的延迟绑定——的效果：

```Racket
(define seller
 (OBJECT-DEL root ()
  ([method price (prod)
           (* (case prod
                [(1) (-> self price1)]
                [(2) (-> self price2)])
              (-> self unit))]
   [method price1 () 100]
   [method price2 () 200]
   [method unit () 1])))
(define broker
 (OBJECT-DEL seller ()
  ([method unit () 2])))

> (-> seller price 1)
100
> (-> broker price 1)
200
```

## 4.3 用原型编程

具有类似我们在本章中介绍的委托机制的基于对象的语言被称为**基于原型的语言**（prototype），例如Self，JavaScript和AmbientTalk等等。这些语言擅长什么？如何使用原型编程？

### 4.3.1 单例和特殊对象

由于对象可以无中生有地创建（即，用类似于OBJECT-DEL的对象字面表达式创建），所以自然地可以创建独一无二的对象。与基于类的语言需要一个特定的设计模式（称为单例(Singleton)）相反，基于对象的语言非常适合这种情况，也适合创建“特殊”对象（下面会详细介绍）。

我们先来考虑布尔值的面向对象表示和简单的if-then-else控制结构。有多少种布尔值？只有两个：真和假。所以我们可以创建两个独立的对象，true和false来表示它们。在像Self和Smalltalk这样的纯面向对象的语言中，像if-then-else，while等这样的控制结构在语言中不是基本指令。相反，它们被定义为某些对象的方法。我们来考虑if-then-else的情况。我们可以给一个布尔值传两个thunk（译注，无参数的lambda，即`(lambda () ...)`），一个真thunk和一个假thunk；如果布尔值**是**true，它会调用真thunk；如果它**是**false，它会调用假thunk。

```Racket
(define true
  (OBJECT-DEL root ()
    ([method ifTrueFalse (t f) (t)])))
 
(define false
  (OBJECT-DEL root ()
    ([method ifTrueFalse (t f) (f)])))
```

怎么能使用这些对象？举个例子：

```Racket
(define light
 (OBJECT-DEL root
   ([field on false])
   ([method turn-on () (set! on true)]
    [method turn-off () (set! on false)]
    [method on? () on])))

 
> (-> (-> light on?) ifTrueFalse (λ () "灯开了")
                                 (λ () "灯关了"))
"灯关了"
> (-> light turn-on)
> (-> (-> light on?) ifTrueFalse (λ () "灯开了")
                                 (λ () "灯关了"))
"灯开了"
```

对象true和false是布尔值的两种唯一表示。任何依赖某个表达式为真或假的条件机制都可以类似地定义为这两个对象的方法。这就是动态分发！

Smalltalk中的布尔值和控制结构就是这么定义的，不过，由于Smalltalk是基于类的语言，它们的定义更加复杂些。用你最喜欢的基于类的语言来试试看。

我们再来看一个基于对象语言的实用例子：特殊（exceptional）对象。先来回顾一下普通点对象的定义，一般是调用工厂函数make-point创建的：

```Racket
(define (make-point x-init y-init)
  (OBJECT-DEL root
    ([field x x-init]
     [field y y-init])
    ([method x? () x]
     [method y? () y])))
```

假设我们要引入一个特殊的点对象，它的特殊性在于坐标是**随机的**，每次访问都会改变。我们可以简单地定义random-point为一个独立的对象，其`x?`和`y?`方法执行计算而不是访问存储的状态：

```Racket
(define random-point
  (OBJECT-DEL root ()
    ([method x? () (* 10 (random))]
     [method y? () (-> self x?)])))
```

请注意，random-point没有声明任何字段。当然，因为在OOP中我们依赖的是对象的接口，两种表示可以共存。

### 4.3.2 通过委托共享

上面讨论的例子突出了基于对象的语言的优点。现在让我们看看实际使用中的委托。首先，委托可以用来分解对象之间的**共享行为**。考虑这种情况：

```Racket
(define (make-point x-init y-init)
  (OBJECT-DEL root
    ([field x x-init]
     [field y y-init])
    ([method x? () x]
     [method y? () y]
     [method above (p2)
             (if (> (-> p2 y?) (-> self y?))
                 p2
                 self)]
     [method add (p2)
             (make-point (+ (-> self x?)
                            (-> p2 x?))
                         (+ (-> self y?)
                            (-> p2 y?)))])))
```

创建的所有点对象都具有相同的方法，因此这些行为可以移至公共的父对象（通常称为原型(prototype)）中，以实现共享。所有的行为都应该移到原型中吗？如果我们想要允许点的不同表示，比如前面的随机点（它根本不含任何字段！），就不该这么做。

因此，我们可以定义point原型，它提取了above和add方法，它们的实现对所有点都是一样的：

```Racket
(define point
  (OBJECT-DEL root ()
    ([method above (p2)
             (if (> (-> p2 y?) (-> self y?))
                 p2
                 self)]
     [method add (p2)
             (make-point (+ (-> self x?)
                            (-> p2 x?))
                         (+ (-> self y?)
                            (-> p2 y?)))])))
```

> `point`中必须提供的选择器（accessor）方法可以定义为abstract（抽象）方法，如果我们的语言支持此概念的话。Smalltalk就可以这么做，这种方法被调用的话就会抛出异常。

请注意，作为一个独立的对象，point没有意义，因为它给自己发送自已也不理解的消息。但它可以作为原型，其他点可以扩展之。比如说普通的点，用make-point创建，包含字段x和y：

```Racket
(define (make-point x-init y-init)
  (OBJECT-DEL point
    ([field x x-init]
     [field y y-init])
    ([method x? () x]
     [method y? () y])))
```

也可以是特殊的点：

```Racket
(define random-point
  (OBJECT-DEL point ()
    ([method x? () (* 10 (random))]
     [method y? () (-> self x?)])))
```

正如我们所说的，这些不同类型的点相互合作，它们都理解point原型中定义的消息：

```Racket
> (define p1 (make-point 1 2))
> (define p2 (-> random-point add p1))
> (-> (-> p2 above p1) x?)
8.90016724570533
```

同样，我们可以用委托来共享对象之间的**状态**。例如，考虑一组共享相同x坐标的点：

```Racket
(define 1D-point
  (OBJECT-DEL point
    ([field x 5])
    ([method x? () x]
     [method x! (nx) (set! x nx)])))
 
(define (make-point-shared y-init)
  (OBJECT-DEL 1D-point
    ([field y y-init])
    ([method y? () y]
     [method y! (ny) (set! y ny)])))
```

所有由make-point-shared创建的对象共享同一个父对象`1D-point`，由它决定x坐标。如果改变`1D-point`，自然会反映到所有子对象上：

```Racket
> (define p1 (make-point-shared 2))
> (define p2 (make-point-shared 4))
> (-> p1 x?)
5
> (-> p2 x?)
5
> (-> 1D-point x! 10)
> (-> p1 x?)
10
> (-> p2 x?)
10
```

## 4.4 Self的延迟绑定与模块化

> 参见《[Why of Y](http://www.dreamsongs.com/NewFiles/WhyOfY.pdf)》。

在OBJECT-DEL语法抽象的定义中，注意我们在消息发送的定义中使用了自我调用的模式`(obj obj)`。我们之前也用到过自我调用模式，是在不赋值的情况下实现递归绑定（译注，参见PLAI）。

> 想想C++和Java等主流语言是怎么做的：它们怎么解决可扩展性(extensibility)和脆弱性(fragility)之间的折衷？

OOP的这个特性也被称为“开放式递归”（open recursion）：任何子对象都可以重新定义其父对象的（父对象的）方法。当然，这种机制有利于**可扩展性**（extensibility），因为我们可以扩展对象的任何方面，而不必事先预见怎么扩展。另一方面，开放式递归使得软件变得更加**脆弱**（fragile），因为以不可预见、不正确的方式扩展对象变得非常容易。想象一下可能出问题的情况，然后考虑可行的替代设计。为了进一步阐明脆弱性，可以考虑对象的黑盒组合情况：有两个对象，各自独立开发，然后把它们放入委托关系中。可能会出什么问题？

## 4.5 词法作用域和委托

正如之前所讨论的，在我们的系统中可以定义[嵌套的对象](./chap2.md#25-嵌套的对象)。词法嵌套与委托之间的关系蛮有意思的，值得讨论一下。考虑下面的例子：

```Racket
(define parent
 (OBJECT-DEL root ()
   ([method foo () 1])))
 
(define outer
 (OBJECT-DEL root
    ([field foo (λ () 2)])
    ([method foo () 3]
     [method get ()
             (OBJECT-DEL parent ()
                ([method get-foo1 () (foo)]
                 [method get-foo2 () (-> self foo)]))])))
 
(define inner (-> outer get))

> (-> inner get-foo1)
2
> (-> inner get-foo2)
1
```

可以看到，在`get-foo1`中，查找的是词法环境中的自由标识符，而在`get-foo2`中，查找的是委托链中未知消息。这点需要澄清，因为Java程序员习惯的是`this.foo()`等同于`foo()`。在许多同时支持词法嵌套和某种形式的委托（如继承）的语言中，情况并非如此。

> 其他语言对此有不同的处理。参见Newspeak和AmbientTalk。

Java是怎么处理的？ 试试就知道了！继承链屏蔽（shadow）了词法链：使用`foo()`时，如果能在超类中找到方法，则会调用该方法；只有在找不到方法时，才使用词法环境（即outer对象中的foo）。因此，对outer对象的引用是非常脆弱的。这就是为什么Java支持额外的语法形式`Outer.this`来引用外层对象。当然，如果直接外层对象的类中找不到方法，那么就继续在它的超类中查找，而不是往词法链上。

## 4.6 委托模型

我们在这里实现的委托模型只是基于原型的语言的设计空间中的一个点。请自行研究Self，JavaScript和AmbientTalk的文档以了解其设计。你还可以修改我们的对象系统，让其支持不同的模型，比如说JavaScript模型。

## 4.7 克隆

在我们的语言中（在JavaScript中也是一样），对象都是**无中生有的**创建的：要么从头创建对象，要么我们有个函数，它的作用是为我们执行对象的创建。历史上，基于原型的语言（如Self）提供了另一种创建对象的方法：克隆(clone)现有对象。这种方法类似于我们经常进行的文本（包括代码！）的复制—粘贴—修改操作：从某个类似的对象开始，克隆之，然后修改该克隆（比如说，添加方法，更改字段）。

当克隆对象和委托同时存在时，就会出现克隆操作是**深**（deep）还是**浅**（shallow）的问题。浅克隆返回的对象和原始对象共享父对象。深克隆返回的对象的父对象是原始对象的父对象的克隆，并依此类推：整个委托链都被克隆。

这里我们不在详细地研究克隆。然而，你应该思考一下，在我们的语言中支持克隆难易如何。由于对象实际上（通过宏展开）被编译成函数，所以问题归结为闭包的克隆。不幸的是，Scheme不支持此操作。出现了源语言和目标语言之间不匹配的情况（想想PLAI第12章）。甘瓜苦蒂！
