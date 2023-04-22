# 7 充满可能的世界

本书在Scheme中简单地逐步构建了对象系统，但我们只阐述了面向对象编程语言的一些基本概念。在语言设计中，总是存在各种各样的可能性有待探索，比如同样的想法的变种、延伸等。

这里给出一些（有限的/随意挑选的）特性和机制，你可以在某些现有的面向对象编程语言中找到，但在我们的讨论中没有涉及。你可以试试将其集成到对象系统中。当然，更有意思的是，你该自己去思考其他特性，还有研究现有的语言并弄清楚如何整合其独特的特性。

- 方法的可见性：public / private
- 声明覆盖超类中方法的方法：override
- 声明不能被覆盖的方法：final
- 声明预期将被继承的方法：inherit
- 可扩展的方法：inner
- 接口（Interface）：能理解的消息的集合
- 检查某个对象是否是某个类的实例的协议，检查某个类是否实现某个接口的协议，……
- 超类的正确初始化协议，实名初始化属性
- 多重继承
- Mixins
- Traits
- 类作为对象，元类（metaclass），……

还有许多优化，例如：

- 计算字段的偏移量（offset），以直接访问字段
- 用于直接方法调用的虚函数表（vtable）和索引（indice）

这里以习题的形式介绍两种机制，接口和mixin，以及它们的组合（即使用接口实现mixin规范）。

## 7.1 接口

（在我们的语言中）引入定义接口的新的语法形式（接口可以扩展超接口）：

```Racket
(interface (superinterface-expr ...) id ...)
```

引入新的类定义语法，使其可以实现（多个）接口：

```Racket
(CLASS* super-expr (interface-expr ...) decls ...)
;decls为类主体中的申明
```

例如：

```Racket
(define positionable-interface
  (interface () get-pos set-pos move-by))

(define Figure
  (CLASS* Root (positionable-interface)
     ....))
```

扩展类的协议，使之能检查给定类是否实现了特定接口：

```Racket
> (implements? Figure positionable-interface)
#t
```

## 7.2 Mixin

Mixin是将超类参数化的类声明。当类的继承层次结构中存在共享部分，而单继承又不足以表达时，可以通过组合mixin来创建新类。

因为我们的类由函数实现的，是一等的值（first-class value），所以mixin的实现毫不费力。

```Racket
(define (foo-mixin cl)
  (CLASS cl (....) (....)))

(define (bar-mixin cl)
  (CLASS cl (....) (....)))

(define Point (CLASS () ....))

(define foobarPoint
  (foo-mixin (bar-mixin Point)))
(define fbp (foobarPoint 'create))
....
```

Mixin和接口结合，可以检查给定的基类是否实现了一组特定的接口。定义MIXIN语法形式：

```Racket
(MIXIN (interface-expr ...) decl ...)
```

这应该是个函数，其输入是基类，先检查该基类实现了所有指定的接口，然后返回（用给定的声明）扩展基类所得的新类。
