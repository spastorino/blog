---
title: "Multiple defining uses of Type Alias Impl Traits"
tags: ["rust", "compiler", "taits"]
---

Disclaimer: this blog post comes from some notes I took meanwhile
working on an Rust compiler issue and it's not very polished but I've
decided to publish it anyway.

A [bug was reported to the
compiler](https://github.com/rust-lang/rust/issues/73481) that involves
type checking, inference, traits and in particular type alias impl
traits (TAIT) with multiple defining uses and some other particular
things about them.  In this post we are going to explain how the system
works as I was investigating this myself in order to fix this issue,
what is the issue exactly about and then describe how we've solved the
issue.

First, let's get started with the code that causes the problem:

```rust
#![feature(min_type_alias_impl_trait)]

type X<A, B> = impl Into<&'static A>;

fn f<A, B: 'static>(a: &'static A, _b: B) -> (X<A, B>, X<B, A>) {
    (a, a)
}

fn main() {
    println!("{}", <X<_, _> as Into<&String>>::into(f(&[1isize, 2, 3], String::new()).1));
}
```

If you try to run this program using nightly (with one before the fix
landed) you'll get:

```
[santiago@galago tait_issue (master)]$ cargo run
   Compiling tait_issue v0.1.0 (/tmp/tait_issue)
    Finished dev [unoptimized + debuginfo] target(s) in 0.53s
     Running `target/debug/tait_issue`
Segmentation fault (core dumped)
```

This program should not compile but it does and when you run it you get
a segfault. So, this is a
[soundness](https://en.wikipedia.org/wiki/Soundness) issue in our type
system. We want every program that type checks to be a valid one; but
that is not what happens with this example: the compiler type checks but
the program is invalid.

Let's see how the compiler type checks this and other simpler programs
in order to get a better understanding of what's going on.

## Type checking TAIT: a simple example

Let's type check the following example:

```rust
type X<A> = impl Into<A>;
fn foo<T>(x: T) -> X<T> { x }
```

The idea is that `impl Into<A>` in that position 'desugars' into a kind
of 'existential type', something whose value must be inferred. It is
inferred when there is a "defining use", which is basically a use of the
type alias in a context that defines the value of the "hidden" type.

For the purposes of type checking, is important to consider that the
following code which our example uses, lives on stdlib ...

```rust
impl<T> From<T> for T {
    fn from(t: T) -> T {
        t
    }
}

impl<T, U> Into<U> for T
where
    U: From<T>,
{
    fn into(self) -> U {
        U::from(self)
    }
}
```

So written as program clauses, from stdlib we have:
`<T> T: From<T>`
`<T, U> T: Into<U> if U: From<T>`

Let's type check `foo`:

First of all, as we've said previously we need to convert the return
type, which would be `impl Into<T>` into an existential type ...  So our
`foo` function will look like this:

```rust
fn foo<T>(x: T) -> ?X { x }
```

and we will have the following clause:
`?X: Into<T>` because `X<T>` was really the return type.

Type checking `foo`'s body, which is not important for the purposes of
this work, will give us that the type being returned is `T` because `x`
is returned and its type is `T`.
Then, we can deduce the following clause:
`T = ?X`

Unifying those two clauses we end up with:
`T: Into<T>`

Then, unifying the clause `<T, U> T: Into<U> if U: From<T>` with our
current program clause we have `<T> T: Into<T> if T: From<T>`. So `T:
Into<T>` holds if `T: From<T>` holds, and `T: From<T>` holds because
it's one of the clauses that also comes from stdlib.

So `foo` signature type checks and `?X` is `T`.

What happens after that is that we use the inferred `?X` value `T`, to
figure out what's the real type of `X<A>`, which in our case we conclude
that it's `T`.

## Type Alias Impl Traits Rules

Let's consider the following example:

```rust
type X<A, B> = impl Sized;
```

In this case, what would be the "hidden" type?, it could either be `A`
or `B`, those are types that the inference context can use to define the
actual types.

If the defining use is:

```rust
fn foo<T, Z>(x: T, y: Z) -> X<T, Z> { x }
```

the "hidden" type would be `A`. Type alias can be treated as type `X<A, B> = A`.

If the defining use is:

```rust
fn foo<T, Z>(x: T, y: Z) -> X<T, Z> { y }
```

the "hidden" type would be `B`. Type alias can be treated as type `X<A, B> = B`.

If the defining use is:

```rust
fn foo<T>(x: T) -> X<T, T> { x }
```

that would be ambiguous, it could either be `A`, `B` or a combination of both.

So, the code is rejected by the compiler.

There's a similar problem with the following example:

```rust
type X<A> = impl Sized;
fn foo() -> X<u32> { 22_u32 }
```

in this case, the type of `X<A>` could either be `u32` or just `A`.
So, the compiler again rejects the code.

So in order to avoid this ambiguity, when we have a "defining use" of a
TAIT, the generic arguments to that TAIT must all be unique generic
arguments from the surrounding scope.

In our previous examples we saw that we used `u32` which is not generic
so the compiler rejected the code and in the other example we've used
`<T, T>` which is generic but the generic arguments are not unique, so
the compiler rejected it too.

## Back to the reported issue

```rust
type X<A, B> = impl Into<&'static A>;

fn f<A, B: 'static>(a: &'static A, _b: B) -> (X<A, B>, X<B, A>) {
    (a, a)
}
```

As we see in this example, there are two defining uses of `X`, `X<A, B>`
and `X<B, A>` and each of those uses follow the rules. Both reference
only generic parameters from `f` and are both unique.  The bug happens
because we do not recognize that there are two different uses of `X`.
What we do today is that we create just one inference variable `?X` for
both uses and we ignore one of the uses.  What we should do is treat
each use separately, by creating two inference variables, let's say
`?X1` and `?X2`.

In the following post we'll see how we've implemented this change that
allowed the compiler to create different inference variable for each
different defining use.

## Implementing the idea in the compiler

I've placed a [PR #86118](https://github.com/rust-lang/rust/pull/86118) which implements the previously discussed idea.

During type check, for each **defining use** of a TAIT, we replace those
uses with inference variables in
[`instantiate_opaque_types`](https://github.com/rust-lang/rust/blob/835150e7/compiler/rustc_trait_selection/src/opaque_types.rs#L153-L185).
Following down the path taken by `instantiate_opaque_types`, we will be
calling
[`fold_opaque_ty`](https://github.com/rust-lang/rust/blob/835150e7/compiler/rustc_trait_selection/src/opaque_types.rs#L1029-L1035)
for each opaque type that shows up meanwhile type checking. That's going
to replace each of the opaque types with an inference variable.

<!-- more -->

The problem we've is due [this
line](https://github.com/rust-lang/rust/blob/835150e7/compiler/rustc_trait_selection/src/opaque_types.rs#L1043).
Using `def_id` as the key, we would be getting the same inference
variable for both `X<A, B>` and `X<B, A>` defining uses. So, as stated
previously we need to use `def_id` and `substs` as part of the key in
order to differentiate things like `X<A, B>` from `X<B, A>`. 

The first naive thing to try to do is to change
[OpaqueTypeMap](https://github.com/rust-lang/rust/blob/835150e7/compiler/rustc_trait_selection/src/opaque_types.rs#L19)
to be, instead of a `DefId` -> `OpaqueTypeDecl` map, be just `DefId,
SubstsRef` -> `OpaqueTypeDecl` map. I've tried that path and it gives a
lot of troubles because the new key pair needs to implement `HashStable`
and stuff like that, so I'm not taking this path in the blog post :).

What we've done instead is to implement a `VecMap` structure which will
sort the previous issue, but also, we got rid of `HashMap` which was an
overkill for our use case. This "map" would not have a lot of elements
in it.

Considering all this, please [check out the provided
PR](https://github.com/rust-lang/rust/pull/86118), which is already
merged. Most of the changes in the PR that are not explained in this
post, are fallouts produced by this mentioned key change, where we
substituted `DefId` as the key of the map with `DefId` and `SubstsRef`
and also I've removed `SubstsRef` from the produced values of
`OpaqueTypeMap` given that `SubstsRef` is now part of the key.
