# 6 继承

既然有了类，我们可能需要一个类似于[委托](./chap4.md#42-委托)的机制，以便能够重用和选择性地细化现有的类。因此，我们扩展对象系统，支持**类继承**（class inheritance）。我们将会看到，有许多问题需要处理。像往常一样，我们将逐步讨论。

## 6.1 类的层次结构

先来引入一个类**扩展**另一个类的能力（称为它的**超类**(superclass)）。这里只讨论**单一继承**（single inheritance），一个类只扩展一个类。

> 多重继承。C++

结果就是，类被组织成层次结构。一个类的所有（传递性的）超类被称为其**祖先**；对等的，一个类的传递**子类**（subclass）集称为它的**后代**。

例如：

```Racket
(define Point
  (CLASS extends Root
           ([field x 0])
           ([method x? () (? x)]
            [method x! (new-x) (! x new-x)]
            [method move (n) (-> self x! (+ (-> self x?) n))])))
 
(define ColorPoint
  (CLASS extends Point
           ([field color 'black])
           ([method color? () (? color)]
            [method color! (clr) (! color clr)])))
```

## 6.2 方法查找

当给对象发送消息时，我们在它的类中查找实现此消息的方法，然后调用之。反映到CLASS宏的定义中就是：

```Racket
[(invoke)
 (if (assoc (second vals) methods)
     (apply ((cdr (assoc (second vals) methods)) (first vals)) (cddr vals))
     (error "message not understood"))]
```

有了继承，如果对象收到了一个在其类中找不到方法的消息，我们可以在超类中寻找方法，并依此类推。首先，invoke协议需要细化，分两步进行：第一步是lookup（查找），包括如果在当前类中没有找到方法的话在超类中查找，第二步是实际的invoke步骤。

```Racket
(defmac (CLASS extends superclass
               ([field f init] ...)
               ([method m params body] ...))
  #:keywords field method extends
  #:captures self ? !
  (let ([scls superclass]
        (methods
         (local [(defmac (? fd) #:captures self
                   ((obj-class self) 'read self 'fd))
                 (defmac (! fd v) #:captures self
                   ((obj-class self) 'write self 'fd v))]
           (list (cons 'm (λ (self)
                            (λ params body))) ...))))
    (letrec ([class (λ (msg . vals)
                      (case msg
                        ....
                        [(invoke)
                         (let ((method (class 'lookup (second vals))))
                           (apply (method (first vals)) (cddr vals)))]
                        [(lookup)
                         (let ([found (assoc (first vals) methods)])
                           (if found
                               (cdr found)
                               (scls 'lookup (first vals))))]))])
      class)))
```

CLASS语法抽象扩展了，加了extends子句（这是类定义中新的关键字）。试用这个抽象之前，我们需要在树的顶部定义一个**根**类，以终结方法查找的过程。如下的Root类就可以：

```Racket
(define Root
  (λ (msg . vals)
    (case msg
      [(lookup) (error "message not understood:" (first vals))]
      [else     (error "root class: should not happen: " msg)])))
```

Root直接实现为函数而不使用CLASS形式，所以我们无需指定它的超类（它也没有）。如果收到lookup消息，它会给出消息无法理解的错误。请注意，在此系统中，除了lookup以外的任何消息发送到根类都是错误。

来看一个非常简单的类继承的例子：

```Racket
(define A
  (CLASS extends Root ()
         ([method foo () "foo"]
          [method bar () "bar"])))
(define B
  (CLASS extends A ()
         ([method bar () "B bar"])))

> (define b (new B))
> (-> b foo)
"foo"
> (-> b bar)
"B bar"
```

看起来都对了：向B发送其不理解的消息，如预期那样工作正常，并且发送bar的结果是B的细化而不是A的方法被执行。换一种说法，方法调用被正确的**延迟绑定**（late binding）了。我们说，B中的bar方法**覆盖**（override）了A中定义的同名方法。

再来看个稍微复杂一点的例子：

```Racket
> (define p (new Point))
> (-> p move 10)
> (-> p x?)
10
```

来试试ColorPoint：

```Racket
> (define cp (new ColorPoint))
> (-> cp color! 'red)
> (-> cp color?)
'red
> (-> cp move 5)
hash-ref: no value found for key
  key: 'x
```

发生了什么？看来，我们不能使用ColorPoint的x字段。好吧，我们还没有讨论过在继承中如何处理字段。

## 6.3 字段和继承

来看一下我们目前是怎么处理对象创建的：

```Racket
[(create)
 (make-obj class
           (make-hash (list (cons 'f init) ...)))]
```

问题就在这里：在字典中我们只初始化了当前类声明的字段的值！还需要对祖先类的字段值进行初始化。

###　6.3.1　继承字段

对象应该包含其祖先声明的所有字段的值。因此，当创建类时，我们应该确定它的实例的所有字段。要做到这一点，我们必须扩展类，使其保留所有字段的列表，并能够将该信息提供给任何需要的子类。

```Racket
(defmac (CLASS extends superclass
               ([field f init] ...)
               ([method m params body] ...))
  #:keywords field method extends
  #:captures self ? !
  (let* ([scls superclass]
         [methods ....]
         [fields (append (scls 'all-fields)
                         (list (cons 'f init) ...))])
    (letrec
        ([class (λ (msg . vals)
                  (case msg
                    [(all-fields) fields]
                    [(create) (make-obj class
                                        (make-hash fields))]
                    ....))]))))
```

在类的词法环境中，我们引入新的fields标识符。该标识符绑定到类的实例应该有的全部字段的列表。要获取超类的所有字段，只要向其发送all-fields消息（其实现简单地返回绑定到fields的表）。创建对象时，我们就要用这些字段来创建新的字典。

因为我们给类的词汇表增加了新消息，所以需要想想如果Root收到这个消息该怎么处理：它的所有字段是什么？必须是空表，因为我们不加分辨地使用了append：

```Racket
(define Root
  (λ (msg . vals)
    (case msg
      [(lookup)     (error "message not understood:" (first vals))]
      [(all-fields) '()]
      [else (error "root class: should not happen: " msg)])))
```

来试试这是否有效：

```Racket
> (define cp (new ColorPoint))
> (-> cp color! 'red)
> (-> cp color?)
'red
> (-> cp move 5)
> (-> cp x?)
5
```

太好了！

### 6.3.2 字段的绑定

实际上，还有一个问题我们没有考虑过：如果子类定义了一个字段，其名字已经存在于其祖先之一，会发生什么？

```Racket
(define A
 (CLASS extends Root
        ([field x 1]
         [field y 0])
        ([method ax () (? x)])))
(define B
  (CLASS extends A
         ([field x 2])
         ([method bx () (? x)])))

> (define b (new B))
> (-> b ax)
2
> (-> b bx)
2
```

在这两种情况下，返回的都是绑定到B的x字段的值。换句话说，和方法一样，字段也是延迟绑定的。这合理吗？

> 强封装

我们来想一想：对象的目的是将一些（可能可变的）状态封装在适当的程序接口（方法）之后。显然，对方法延迟绑定是理想的，因为方法是对象的外部接口。那么字段呢？字段应该是隐藏的、对象的内部状态——换种说法，实现的细节，而不是公开的接口。其实，请注意我们的语言到目前为止，甚至不能访问另一个对象除self之外的的字段！那么，至少，对字段的延迟绑定是值得疑问的。

> 私有方法应该延时绑定吗？ 他们是延迟绑定的吗？

来看一下[委托](./chap4.md#42-委托)是怎么处理字段的？那里，字段只是函数的自由变量，所以它们遵从**词法作用域**。对字段来说，这是更合理的语义。在类中定义方法时，其根据该类中直接定义的字段或其超类中的字段。这里的道理是，因为所有这些都是在编写类定义的时候已知的信息。延迟绑定字段意味着对方法中的所有自由变量重新引入了动态作用域：有趣的错误之源和头痛的来源！（想想这样的例子，子类意外地引入与超类中已有名称一样的字段，从而导致混乱。）

### 6.3.3 字段屏蔽

本节讨论如何定义被称为**字段屏蔽**（field shadowing）的语义：类的字段屏蔽超类的同名字段，但是方法总是访问它所在的类或其祖先声明的字段。

具体来说，这意味着一个对象可以为同名字段保存不同的值；使用哪一个取决于具体执行的方法在哪个类定义（这被称为方法的**宿主类**(host class)）。由于这种多重性，只用一个哈希表是不够了。替代方案，我们在类中记录字段的名称，并在对象中保存由值组成的**向量**（vector），通过位置来访问此向量。字段访问将分两步完成：首先根据名称列表确定字段的位置，然后访问对象所持有的向量中对应的值。

例如，对于上面的类A，名称列表是`'(x y)`，创建新的A实例，其值的向量是`#(1 0)`。对于B类，名称列表是`'(x y x)`，新实例中值的向量是`#(1 0 1)`。以这种方式保持字段的优点是，在没有屏蔽的情况下，字段总是在对象内相同的位置中。

要遵从屏蔽的语义，我们（至少）有两个选项。一种方法，我们可以将被屏蔽字段重命，例如B中的字段名变成`'(x0 y x)`，这样B中的方法及其后代只能看到x——也就是B中引入的字段——的最新定义。另一种方法是保持字段名不变，而从结尾开始执行查找：也就是说，我们希望在名称列表中找到字段名**最后**的位置。这里我们选择后一种方案。

修改CLASS的定义，以引入向量和字段查找策略：

```Racket
....
[(create)
 (let ([values (list->vector (map cdr fields))])
   (make-obj class values))]
[(read)
 (vector-ref (obj-values (first vals))
             (find-last (second vals) fields))]
[(write)
 (vector-set! (obj-values (first vals))
              (find-last (second vals) fields)
              (third vals))]
....
```

创建对象时，我们用初始字段值构造向量。然后，访问字段时，我们用find-last返回的位置来访问此向量。不过，试一下就知道，此路不通！现在也语义和之前一样是错误的。

为什么呢？回忆一下我们是怎么处理字段访问的，即怎么去除`?`语法糖：

```Racket
(defmac (? fd) #:captures self
  ((obj-class self) 'read self 'fd))
```

这里写的表达式是，先询问self是哪个类，然后发送給该类read消息。嗯，但是self是动态绑定到接收方对象的，所以我们总是在要求原来的类访问字段！错误在这里。不应将read消息发送给接收方的类，而是发送给方法的**宿主类**。怎么实现呢？需要一种方法，从方法体找到它的宿主类，或者更好的办法，直接访问宿主类的字段列表。

我们可以将字段列表放在方法的词法环境中，就像self那样，但这样的话程序员可能会意外地影响绑定（与之相反，self一般是面向对象语言中的关键字）。字段列表（以及绑定它的名称）应该是我们的实现内部的东西。既然我们在类中局部定义了`?`和`!`，可以简单地将字段列表fields限定在这些语法定义的范围内；由宏观的卫生扩展来确保用户代码不可能意外地影响fields。

```Racket
....
(let* ([scls superclass]
       [fields (append (scls 'all-fields)
                       (list (cons 'fd val) ...))]
       [methods
        (local [(defmac (? fd) #:captures self
                  (vector-ref (obj-values self)
                              (find-last 'fd fields)))
                (defmac (! fd v) #:captures self
                  (vector-set! (obj-values self)
                               (find-last 'fd fields)
                               v))]
          ....)]))
```

> 这个实现并不理想，因为每次字段访问都会调用find-last（昂贵/线性开销）。可以避免吗？ 如何避免？

请注意，我们现在直接访问fields表，所以无需再向类发送字段访问消息。对于写入字段也是一样。

来试试这一切是否能按预期运行：

```Racket
(define A
 (CLASS extends Root
        ([field x 1]
         [field y 0])
        ([method ax () (? x)])))
(define B
  (CLASS extends A
         ([field x 2])
         ([method bx () (? x)])))

> (define b (new B))
> (-> b ax)
1
> (-> b bx)
2
```

## 6.4 清理类协议

我们引入[类](./chap5.md)之后，又对它的协议（protocol）做了不少改变：

- 将invoke协议分成两部分，引入lookup步骤，其目的仅仅是在类的层次结构中查找方法定义。

- 为了能够检索类的字段，添加了all-fields。在构建类的时候会用到它，获得超类的字段，append到被定义的类的字段上。

- 去除了字段访问的read/write协议，以便正确地确定方法中的字段名称的作用域。

现在是时候反思一下类协议，看看这里的协议是不是最小化的，还是可以去掉一些部分。判断的标准是什么？既然我们正在讨论类的协议，它最好确实是依赖于类来处理消息。例如，之前介绍的read/write协议就可以删除。回忆一下：

```Racket
....
[(read)  (dict-ref (obj-values (first vals)) (second vals))]
[(write) (dict-set! (obj-values (first vals)) (second vals)
                    (third vals))]
....
```

这里有任何东西依赖于类函数中的自由变量（或者说，依赖于类对象的状态）吗？没有，唯一需要的输入是当前对象、要访问的字段的名称，以及可能写入的值。因此，我们可以直接把这些代码放在`?`和`!`的展开中，从而有效地“编译掉”一层不必要的解释。

那么invoke呢？ 来看看，它唯一做的是给自己发送一条消息，这个可以直接在扩展`->`时做，这样调用本质上就独立于类了：

```Racket
(defmac (-> o m arg ...)
  (let ([obj o])
    ((((obj-class obj) 'lookup 'm) obj) arg ...)))
```

类协议的其他部分呢？all-fields、create和lookup都访问了类的内部状态：all-fields访问了fields；create访问了fields和class本身；lookup访问了methods和superclass。所以，我们的类只需要了解这三种信息。

## 6.5 发消息给超类

当某个方法覆盖（override）超类中的方法时，有时候需要能调用超类中的定义。允许这么做就可以支持许多典型的细化模式，例如在执行方法之前或之后添加要做的事情，比如对其参数和返回值的进一步处理等等。这被称作**给超类发送**（super send）。我们选择`-->`作为给超类发送的语法。

先来看一个例子：

```Racket
(define Point
 (CLASS extends Root
          ([field x 0])
          ([method x? () (? x)]
           [method x! (new-x) (! x new-x)]
           [method as-string ()
                   (string-append "Point("
                                  (number->string (? x)) ")")])))
 
(define ColorPoint
 (CLASS extends Point
          ([field color 'black])
          ([method color? () (? color)]
           [method color! (clr) (! color clr)]
           [method as-string ()
                   (string-append (--> as-string) "-"
                                  (symbol->string (? color)))])))

> (define cp (new ColorPoint))
> (-> cp as-string)
"Point(0)-black"
```

请注意，给超类发送使我们能够在ColorPoint的定义中重用和扩展Point中as-string的定义。在Java中，这是通过对super调用方法来完成的，但究竟super是什么？给超类发送的语义是什么？

首先要澄清的是：给超类发送的接收者是啥？在上面的例子中，当使用`-->`时，as-string发送给了哪个对象？self！事实上，super只影响了方法查找。一个常见的误解是，在执行给超类发送时，方法查找从接收方的**超类**开始，而不是从它的类开始。我们来构造一个小例子，看看为什么这是不正确的：

```Racket
(define A
  (CLASS extends Root ()
         ([method m () "A"])))
 
(define B
  (CLASS extends A ()
         ([method m () (string-append "B" (--> m) "B")])))
 
(define C
  (CLASS extends B () ()))
 
(define c (new C))
(-> c m)
```

这个程序返回什么？我们来研究一下。`->`展开为发送lookup给c的类，也就是C。在C中没有m方法，所以转而发送lookup给其超类，B。B找到m对应的方法，并返回之。下一步调用此方法，第一个参数是当前的self（也就是c），接下来是消息的参数，在这里为空。对这个方法求值就需要对string-append的三个参数求值，其中第二个参数是给超类发送。如果使用上述给超类发送的定义，那么m不是在C（接收方的实际类）中查找，而是在B（它的超类）中查找的。B中有m方法吗？是的，我们正在执行的就是它……换句话说，如果这么理解super，上述程序将**不会**终止。

> 一些动态语言，比如Ruby，允许在运行时改变类的继承关系。这在基于原型的语言（如Self和JavaScript）中很常见。

错在哪里？给self发送时，不应该在接收方的超类中查找方法。在这个例子中，我们应该在A中而不是在B中查找m。为此，我们需要知道执行给超类发送的方法的**宿主类的超类**。这个值应该是在方法体中静态绑定还是动态绑定的？我们刚才已经说过了：它是方法的宿主类的超类，不可能动态改变（至少在我们的语言中如此）。好在在方法的词法环境中，我明已经有scls绑定指向超类。所以，我们只需要引入新的局部宏`-->`，其展开请求超类scls来查找消息。`-->`可以被用户代码使用，所以它要被添加到#:captures标识符列表中：

```Racket
(defmac (CLASS extends superclass
               ([field f init] ...)
               ([method m params body] ...))
  #:keywords field method extends
  #:captures self ? ! -->
  (let* ([scls superclass]
         [fields (append (scls 'all-fields)
                         (list (cons 'f init) ...))]
         [methods
          (local [(defmac (? fd) ....)
                  (defmac (! fd v) ....)
                  (defmac (--> md . args) #:captures self
                    (((scls 'lookup 'md) self) . args))]
            ....)])))
```

请注意，lookup现在被发送到当前正在执行的方法的宿主类的超类scls，而不是当前对象的实际类。

```Racket
> (define c (new C))
> (-> c m)
"BAB"
```

## 6.6 继承和初始化

之前已经讨论过，通过引入称为初始器的特殊方法，来[初始化](./chap5.md#55-初始化)对象。一旦对象被创建，在被返回给创建者之前，需要调用它的初始器。

现在有了继承，这个过程变得更巧妙了，因为如果初始器能相互覆盖，可能会忽略一些必要的初始化工作。初始器的工作可能非常具体，我们希望避免子类必须处理所有的细节。如果简单假定处理方法的正常语义，那么子类中的initialize可以根据需要调用超类的初始器。这种自由导致的问题是，在继承的字段还没有一致地初始化时，子类中的初始器就可能开始处理对象了。为了避免这个问题，在Java中，构造函数必须做的第一件事就是调用超类的构造函数（它可以先计算此调用的参数，仅此而已）。即使不在源代码中明确写出，编译器也会添加这个调用。事实上，在VM（虚拟机）层面字节码验证器也会检验这一点：因此，底层的节码操作也无法绕开对超类构造函数的调用。
