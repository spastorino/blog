---
title: "RPITs, RPITITs and AFITs and their relationship"
tags: ["rust", "compiler", "types"]
---

This is the first blog post as part of a series of blog posts that will
try to explain how impl trait in return position inside and outside
traits and async fns in traits works.  This first blog post summarizes
the concepts with some simple examples. In the following ones we would
be explaining a bit about the internal details.

## What is an RPIT?

RPIT stands for Return Position Impl Trait. It's an opaque return type,
so a type whose concrete data structure is not defined in an interface,
exposing as the interface that it just implements the mentioned trait.

```rust
fn odd_integers(start: u32, stop: u32) -> impl Iterator<Item = u32> {
    (start..stop).filter(|i| i % 2 != 0)
}
```

In this example, the RPIT, it's an opaque type defined as `impl
Iterator<Item = u32>`. Basically, a type that implements `Iterator`
whose items are `u32`. Although the function internally has a concrete
type, it is exposed as an opaque type for consumers. So all the callers
know is that it implements `Iterator<Item=u32>`.

To learn more about RPITs, check out the
[RFC](https://github.com/rust-lang/rfcs/blob/master/text/1522-conservative-impl-trait.md).

## What is an RPITIT?

RPITIT stands for Return Position Impl Trait In Trait. It's basically an
RPIT as defined above but defined for a function that lives inside a
trait.  Note that this feature has not been stabilized yet. In order to
use it, you would need to use
`#![feature(return_position_impl_trait_in_trait)]` feature flag.

```rust
trait NewIntoIterator {
    type Item;

    fn into_iter(self) -> impl Iterator<Item = Self::Item>;
}
```

In this example, `impl Iterator<Item=Self::Item>` is an RPIT returned by
`into_iter` and it's also an RPITIT because it lives inside a trait, in
this case `NewIntoIterator`.

On the implementation side as the return type, we can use or a concrete
type that implements `Iterator` or just have the `impl Iterator` RPIT
again:

```rust
// impl example 1:
impl<T> NewIntoIterator for Vec<T> {
    type Item = T;
    
    // can return a concrete type `IntoIter<T>`
    fn into_iter(&self) -> IntoIter<T> {
        ...
    }
}

// impl example 2:
impl NewIntoIterator for MyCollection<T> {
    type Item = T;
    
    // can return an RPIT `impl Iterator<Item = Self::Item>` 
    fn into_iter(self) -> impl Iterator<Item = Self::Item> {
        ...
    }
}
```

To learn more about RPITIT, check the [draft
RFC](https://rust-lang.github.io/impl-trait-initiative/RFCs/rpit-in-traits.html).

## What is an AFIT?

An async function's return type is desugared into `impl Future<Output =
return_type_of_the_fn>`, which we have previously discussed that it's an
RPIT. An AFIT stands for Async Fn In Trait, so an AFIT's return type
would be an RPIT inside a trait, so an RPITIT.  Note that this feature
has not been stabilized yet. In order to use it, you would need to use
`#![feature(return_position_impl_trait_in_trait)]` feature flag.

```rust
trait Service {
    async fn request(&self, key: i32) -> Response;
}
```

is syntactic sugar for:

```rust
trait Service {
    fn request(&self, key: i32) -> impl Future<Output=Response>;
}
```

In this example, we originally have an AFIT (async function in trait),
which gets desugared into `impl Future<Output=Response>` RPITIT.

At this point the connection between the three concepts should be clear.
An AFIT is a particular kind of RPITIT, so there's no AFITs without
RPITITs and an RPITIT is a particular kind of RPIT, so there's no
RPITITs without RPITs either.

To learn more about AFIT check out the [static async fn in trait
RFC](https://rust-lang.github.io/rfcs/3185-static-async-fn-in-trait.html).

## How RPITs work today?

Given the following function that returns an RPIT:

```rust
fn foo<'a>(&'a self) -> impl Debug + 'a { ... }
```

when we do [AST->HIR
lowering](https://rustc-dev-guide.rust-lang.org/lowering.html) we get:

```rust
fn foo<'a>(&'a self) -> Foo<'static, 'a> {
    type Foo<'b, 'a1>: Debug + 'a1;
    ...
}
```

Both the new lifetime `'a1` and the use of `'static` may be very
surprising to you. This is basically the topic for our following blog
post :). Stay tuned.
