# 3 对象的好处和局限性

在编程语言的课程中，我们这样编程：定义数据类型及其变体，在此之上定义操作这些结构体的各种“服务”，所谓服务也即对这些数据结构的各种变种分情况进行处理的子程序。这种编程风格有时被称为“过程式”或“函数设计”的（注意这里的“函数”并不是指“无副作用的”！）。

在《程序语言：应用和解释》中，我们用`define-type`来定义数据类型及其变体，用`type-case`实现对变种按情况处理的子程序。这种编程方法在其他语言中也很常见：C（联合体）、Pascal（变体类型）、ML和Haskell的代数数据类型、纯Scheme的带标记数据。

那么，面向对象编程究竟给我们提供了什么呢？它的缺点是什么呢？事实证明，使用面向对象的语言并不意味着程序就是“面向对象”的。许多Java程序就不是，或者至少是牺牲了对象的某些基本好处的。

> 本章基于William R. Cook 2009年的《On Understanding Data Abstraction, Revisited》（再谈对数据抽象的理解）一文。

本独立章节的目的是，暂时从逐步构建OOP的步骤中抽身，转而对比面向对象和过程式编程，从而明确每种方法各自的优缺点。有趣的是，我们迄今为止构建的简单对象系统完全足够研究对象的基本好处和局限性了——委托、类、继承等都是有趣的特性，但对于对象来说都不是**本质**的。

## 3.1 抽象数据类型

我们先来讨论抽象数据类型（ADT）。ADT是隐藏其表示、只提供对值的操作的数据类型。

例如，**整数的集合**ADT可以定义如下：

```text
adt Set 是
  empty : Set
  insert : Set x Int -> Set
  isEmpty? : Set -> Bool
  contains? : Set x Int -> Bool
```

这种整数集ADT有许多可能的表示。例如，可以使用Scheme的表来实现它：

```Racket
(define empty '())

(define (insert set val)
  (if (not (contains? set val))
      (cons val set)
      set))

(define (isEmpty? set) (null? set))

(define (contains? set val)
  (if (null? set) #f
      (if (eq? (car set) val)
          #t
          (contains? (cdr set) val))))
```

客户程序可以使用ADT值，而无需知道底层的表示法：

```Racket
> (define x empty)
> (define y (insert x 3))
> (define z (insert y 5))
> (contains? z 2)
#f
> (contains? z 5)
#t
```

我们也可以用另一种表示方式来实现ADT集合，比如使用PLAI的define-type机制来创建一个变体类型，将集合编码为链表。

```Racket
(define-type Set
  [mtSet]
  [aSet (val number?) (next Set?)])

(define empty (mtSet))

(define (insert set val)
  (if (not (contains? set val))
      (aSet val set)
      set))

(define (isEmpty? set) (equal? set empty))

(define (contains? set val)
  (type-case Set set
    [mtSet () #f]
    [aSet (v next)
          (if (eq? v val)
              #t
              (contains? next val))]))
```

前面的示例客户程序运行照旧，即使现在底层表示换掉了：

```Racket
> (define x empty)
> (define y (insert x 3))
> (define z (insert y 5))
> (contains? z 2)
#f
> (contains? z 5)
#t
```

## 3.2 用子程序表示

我们也可以把集合看作是由它的**特征函数**定义：该函数读入一个数字，告诉我们这个数字是否是集合的一部分。在这种情况下，集合就是简单的`Int -> Bool`函数。（PLAI一书中，第十二章中在研究环境的**子程序表示**时有提到。）

空集的特征函数是什么？总是返回假的函数。插入一个新元素所获得的集合呢？

```Racket
(define empty (λ (n) #f))

(define (insert set val)
          (λ (n)
            (or (eq? n val)
                (contains? set n))))

(define (contains? set val)
  (set val))
```

由于集合由其特征函数表示，`contains?`只需将该函数应用于该元素。请注意，客户程序还是完全不受干扰：

```Racket
> (define x empty)
> (define y (insert x 3))
> (define z (insert y 5))
> (contains? z 2)
#f
> (contains? z 5)
#t
```

集合的子程序表示给我们带了了什么？灵活性！例如，我们可以定义所有偶数的集合：

```Racket
(define even
  (λ (n) (even? n)))
```

我们前面考虑的任何ADT表示，都不能完整地表示这个集合。（为什么？）我们甚至可以定义非确定的集合：

```Racket
(define random
  (λ (n) (> (random) 0.5)))
```

使用子程序表示，我们可以更自由地定义集合，此外它们同样可以与已有的集合操作交互！

```Racket
> (define a (insert even 3))
> (define b (insert a 5))
> (contains? b 12)
#t
> (contains? b 5)
#t
```

相反，在上面我们看到的ADT表示中，不同的表示法之间不能互操作。列表实现集合的值不能被结构体实现的操作使用，反之亦然。ADT从表示中抽象出来，但一次只允许**一种表示**。

## 3.3 对象

从本质上讲，**函数实现的集合就是对象**！请注意对象并**未**抽象出类型：函数实现的集合的类型非常具体：它是`Int -> Bool`的函数。当然，正如我们在前面的章节中看到的，对象是函数的泛化，它可以有多个方法。

### 3.3.1 对象的接口

我们可以定义**对象接口**（interface）的概念，也就是某个对象所有方法的型签（类型签名，signature）：

```text
interface Set 是
  contains? : Int -> Bool
  isEmpty? : Bool
```

使用我们的简单对象系统实现集合对象：

```Racket
(define empty
  (OBJECT ()
          ([method contains? (n) #f]
           [method isEmpty? () #t])))

(define (insert s val)
  (OBJECT ()
          ([method contains? (n)
                   (or (eq? val n)
                       (-> s contains? n))]
           [method isEmpty? () #f])))
```

请注意，empty是个对象，insert是返回对象的工厂函数。集合对象实现了Set接口。`empty`对象不包含任何值，它的`isEmpty？`返回`#t`。`insert`返回一个新对象，它的`contains?`方法类似于前文中集合的特征函数，而`isEmpty?`返回`#f`。

客户程序中，构造集合部分不用变，与集合对象交互部分就必须用消息发送了：

```Racket
> (define x empty)
> (define y (insert x 3))
> (define z (insert y 5))
> (-> z contains? 2)
#f
> (-> z contains? 5)
#t
```

请注意，对象接口本质上就是高阶类型：方法是函数，所以传递对象就是传递函数组。这是高阶函数式编程的推广。面向对象的程序本质上是高阶的。

### 3.3.2 面向对象编程的原则

**原则：对象只能通过其他对象的公共接口来访问它们**

一旦创建了对象，比如上面的z（所绑定的），对它**唯一**能做的就是通过发送消息进行交互。不能“打开对象”。对象的任何属性都不可见，可见的只有它的接口。换一种说法：

**原则：对象只对自己有详细的了解**

这与ADT值有本质区别：在`type-case`的处理中（回忆一下ADT实现中用`define-type`实现的`contains?`），我们打开值，从而直接访问其属性。ADT提供封装，但为ADT的客户提供；不为其实现提供。对象在这方面更进一步。即使是对象的方法，其实现也不能访问除自身以外对象的属性。

由此我们可以得出另一个基本原则：

**原则：对象就是所有对其可能进行的观测的集合，这些观测通过对象接口定义**

这是一条强原则，它表明，如果两个对象在对于特定实验（即一组观测）表现相同，那么它们应该是不可区分的。这意味着使用等值判定操作（如指针相等）违反了OOP的这个原则。使用Java中的`==`，我们可以区分即使是**行为**一致的两个对象。

### 3.3.3 可扩展性

上述原则可以被认为是OOP的本质特征。正如Cook所说：“ _任何允许区分多个抽象表示的编程模型都**不是**面向对象的_ ”。

组件对象模型（COM）是实践中最纯粹的OO编程模型之一。COM遵守上述所有的原则：没有内置的相等性，没有办法确定某个对象是否是某个类的实例。因此COM程序是高度可扩展的。

请注意，对象的可扩展性实际上完全独立于继承！（我们的语言甚至还没有类。）它来自对接口的使用。

### 3.3.4 那Java呢？

Java不是一种纯粹的面向对象的语言，并不是因为它有原始类型（primitive type，也有称作内置类型、基础类型或者基本类型），而是因为它支持的许多操作违反了我们上面描述的原则。Java内置支持相等`==`、`instanceof`、转换为类类型，这使得两个对象即使行为一致，也可以被区分。在Java中，可以声明一个方法，根据类来接受对象，而不是根据它们的接口（在Java中，类名也是类型）。当然还有就是，Java允许对象访问其他对象的内部（公有字段当然可以，但即使私有字段同一类的对象也可以访问！）。

这意味着Java也支持ADT风格的编程。这没有什么不对的！但重要的是了解这所涉及的设计上的取舍，然后做出明智的选择。例如，在JDK中，某些类在表面上尊重OO原则（允许可扩展性），但其实现使用ADT技术（不可扩展，但更高效）。如果你有兴趣，参见`List`接口和`LinkedList`实现。

在Java中，“纯OO”编程基本上就是不使用类名称作为类型（即只在`new`之后使用类名），并且从不使用内置的相等（`==`）。

## 3.4 可扩展性问题

面向对象程序设计通常被认为是软件可扩展性方面的灵丹妙药。但是，“可扩展”究竟意味着什么呢？

可扩展性问题说的是如何定义数据类型（结构＋操作），使之能够支持两种形式的扩展：添加新的表示变体，或添加新的操作。

> 这里，ADT的意思遵从Cook的用法。然而我们需要澄清，这里对扩展性问题的讨论实际上将对象与变体类型(variant type)（即代数数据类型(algebraic data types)）进行对比。我们关心的是可扩展的**实现**。这里不关心界面的抽象。

事实表明，ADT和对象分别都能很好地支持可扩展性的一个维度，但是在另一维度就不行了。让我们用一个众所周知的例子来研究此问题：简单表达式的解释器。

### 3.4.1 ADT

先来考虑ADT的做法。表达式的数据类型有三种变体：

```Racket
(define-type Expr
   [num  (n number?)]
   [bool (b boolean?)]
   [add (l Expr?) (r Expr?)])
```

接下来定义解释器，这是一个函数，用type-case处理抽象语法树：

```Racket
(define (interp expr)
   (type-case Expr expr
      [num (n) n]
      [bool (b) b]
      [add (l r) (+ (interp l) (interp r))]))
```

这是一道很好的PLAI练习题。举个例子：

```Racket
> (define prog (add (num 1)
                    (add (num 2) (num 3))))
> (interp prog)
6
```

#### 扩展：新的操作

先来考虑给表达式添加一个新操作。除了对表达式进行解释，我们还想做类型检查，也就是确定它将算得的值的类型（在这里，是`number`或`boolean`）。这很简单，但是能检测到解释过程中出现的失败的情况，比如对两个不是数字的东西进行相加操作：

```Racket
(define (typeof expr)
  (type-case Expr expr
    [num (n) 'number]
    [bool (b) 'boolean]
    [add (l r) (if (and (equal? 'number (typeof l))
                        (equal? 'number (typeof r)))
                   'number
                   (error "类型错误：并非数"))]))
```

求一下之前那个程序的类型：

```Racket
> (typeof prog)
'number
```

我们的类型检查器会拒绝不合理的程序：

```Racket
> (typeof (add (num 1) (bool #f)))
类型错误：并非数
```

反思一下这个扩展案例，我们看到一切都很顺利。想要新的操作，我们只需要定义新的函数。这种扩展是模块化的，因为只需要在一个地方新加定义。

#### 扩展：新的数据

接下来考虑另一个维度的可扩展性：添加新的数据变体。假设我们扩展这里的简单语言，增加新的表达式：`ifc`。扩展后数据类型的定义是：

```Racket
(define-type Expr
  [num  (n number?)]
  [bool (b boolean?)]
  [add (l Expr?) (r Expr?)]
  [ifc (c Expr?) (t Expr?) (f Expr?)])
```

修改`Expr`的定义加上这个新变体破坏了所有现有的函数定义！`interp`和`typeof`都不再成立，因为它们用`type-case`对表达式“按类型处理”，但是并没有处理`ifc`的情况。我们需要修改它们，加上对`ifc`的处理：

```Racket
(define (interp expr)
  (type-case Expr expr
    [num (n) n]
    [bool (b) b]
    [add (l r) (+ (interp l) (interp r))]
    [ifc (c t f)
         (if (interp c)
             (interp t)
             (interp f))]))

(define (typeof expr)
  (type-case Expr expr
    [num (n) 'number]
    [bool (b) 'boolean]
    [add (l r) (if (and (equal? 'number (typeof l))
                        (equal? 'number (typeof r)))
                   'number
                   (error "类型错误：并非数"))]
    [ifc (c t f)
         (if (equal? 'boolean (typeof c))
             (let ((type-t (typeof t))
                   (type-f (typeof f)))
               (if (equal? type-t type-f)
                   type-t
                   (error "类型错误：两个分支的类型不同")))
             (error "类型错误：并非布尔值"))]))
```

程序是正确的：

```Racket
> (define prog (ifc (bool false)
                    (add (num 1)
                         (add (num 2) (num 3)))
                    (num 5)))
> (interp prog)
5
```

这种情况下的可扩展性就不怎么样了。我们必须修改数据类型的定义，然后修改所有的函数。

总而言之，使用ADT，添加新的操作（如`typeof`）是模块化的所以很容易，但添加新的数据类型（例如`ifc`）则不是模块化的所以非常麻烦。

### 3.4.2 OOP

对象在这些场景下表现如何？

我们从面向对象版本的解释器开始：

```Racket
(define (bool b)
  (OBJECT () ([method interp () b])))

(define (num n)
  (OBJECT () ([method interp () n])))

(define (add l r)
  (OBJECT () ([method interp () (+ (-> l interp)
                                   (-> r interp))])))
```

请注意，遵循面向对象的设计原则，每个表达式对象都知道如何解释自己。程序中不存在某个中央解释器能处理所有的表达式。解释程序是通过给该程序发送`interp`消息来完成：

```Racket
> (define prog (add (num 1)
                    (add (num 2) (num 3))))
> (-> prog interp)
6
```

#### 扩展：新的数据

要添加新的数据，比如条件对象ifc，可以简单地定义新的对象工厂，其中包含该新对象处理interp消息的定义：

```Racket
(define (ifc c t f)
  (OBJECT () ([method interp ()
                      (if (-> c interp)
                          (-> t interp)
                          (-> f interp))])))
```

现在可以解释包含条件的程序了：

```Racket
> (-> (ifc (bool #f)
           (num 1)
           (add (num 1) (num 3))) interp)
4
```

这表明，与ADT相反，使用OOP添加新类型的数据是直接的、模块化的：只需创建新对象即可。对比ADT，这是明显的优势。

#### 扩展：新的操作

但在得出结论，认为OOP是软件可扩展性的灵丹妙药之前，我们必须考虑另一种扩展场景：添加操作。假设我们和以前一样，需要检查程序的类型。这意味着表达式对象现在还需要理解“typeof”消息。要做到这一点，我们就必须修改所有的对象定义：

```Racket
(define (bool b)
  (OBJECT () ([method interp () b]
              [method typeof () 'boolean])))

(define (num n)
  (OBJECT () ([method interp () n]
              [method typeof () 'number])))

(define (add l r)
  (OBJECT () ([method interp () (+ (-> l interp)
                                   (-> r interp))]
              [method typeof ()
                      (if (and (equal? 'number (-> l typeof))
                               (equal? 'number (-> r typeof)))
                          'number
                          (error "类型错误：并非数"))])))

(define (ifc c t f)
  (OBJECT () ([method interp ()
                      (if (-> c interp)
                          (-> t interp)
                          (-> f interp))]
              [method typeof ()
                      (if (equal? 'boolean (-> c typeof))
                          (let ((type-t (-> t typeof))
                                (type-f (-> f typeof)))
                            (if (equal? type-t type-f)
                                type-t
                                (error "类型错误：两个分支的类型不同")))
                          (error "类型错误：并非布尔值"))])))
```

程序是正确的：

```Racket
> (-> (ifc (bool #f) (num 1) (num 3)) typeof)
'number
> (-> (ifc (num 1) (bool #f) (num 3)) typeof)
类型错误：并非布尔值
```

这个可扩展性场景下，我们被迫修改所有的代码才能添加新方法。

总而言之，对对象来说，添加新的数据类型（例如ifc）模块化所以容易，但添加新的操作（例如typeof）不模块化所以麻烦。

请注意，这就是ADT的对偶情况！

## 3.5 不同形式的数据抽象

> Cook的论文更深入地讨论了此类数据抽象之间的比较，不可不看！

ADT和对象是不同形式的数据抽象，各有优劣。

ADT的表示类型是私有的，无法篡改或扩展。这对推理（分析）和优化来说是好的。但它（同时）只允许一种表示。

对象拥有行为接口，因此可以随时定义新的实现。这对灵活性和可扩展性来说是好的。但这使得分析代码变得困难，并且使某些优化成为不可能。

这两种抽象形式也支持不同形式的模块化扩展。在ADT上可以模块化地添加新操作，但是支持新的数据变体就很麻烦。面向对象的系统可以模块化地添加新的表示法，但添加新的操作意味着大量的修改。

有一些方法可以绕开此折衷。比如说，在对象的接口中可以公开某些实现细节。这会牺牲一些可扩展性，但恢复某些优化的可能性。所以，这里根本的问题是设计上的问题：我们究竟需要什么？

现在你可以明白，为什么许多语言（同时）支持这两种数据抽象。
