---
title: "How to Use Rust Non Lexical Lifetimes on Nightly"
tags: ["rust", "lifetimes"]
---

[Niko Matsakis](https://twitter.com/nikomatsakis), [Paul
Faria](https://twitter.com/Nashenas88) and
[I](https://twitter.com/spastorino) have been working on Non Lexical
Lifetimes (NLL) during the [impl
period](https://internals.rust-lang.org/t/announcing-the-impl-period-sep-18-dec-17/5676).
The work has landed on master and you can use it right now by installing
Rust nightly.

<!--more--> 

If you don’t know what Non Lexical Lifetimes are, you should read the
[RFC](https://github.com/rust-lang/rfcs/blob/master/text/2094-nll.md)
first. The idea of this post is to show how to use NLL right now. It’s
not my intention to cover the theory behind it or how it solves all the
problems it solves, that’s already explained out there. So, if you want
to know more about lifetimes and non lexical lifetimes, I recommend you
to read the RFC and investigate pull requests.
Maybe this search is useful
[https://github.com/rust-lang/rust/pulls?utf8=✓&q=nll+is%3Apr+is%3Aclosed](https://github.com/rust-lang/rust/pulls?utf8=%E2%9C%93&q=nll+is%3Apr+is%3Aclosed).

So let’s try non lexical lifetimes out with some examples.
First of all you need to install nightly if you don’t have it.
Go ahead and run `rustup install nightly`.

Let’s take a look at a first contrived example that does not compile,
using current lexical lifetimes, which are scope based.

```rust
#![allow(unused_variables)]

fn main() {
    let mut x = 22;

    let p = &mut x; // mutable borrow

    println!("{}", x); // later used
}
```
[Run](https://play.rust-lang.org/?gist=a0a588b64273f2031f49d8b892e7d938&version=nightly)

This does not compile because `x` is mutably borrowed and later used
within the same scope.

```
error[E0502]: cannot borrow `x` as immutable because it is also borrowed as mutable
 --> src/main.rs:8:20
  |
6 |     let p = &mut x; // mutable borrow
  |                  - mutable borrow occurs here
7 | 
8 |     println!("{}", x); // later used
  |                    ^ immutable borrow occurs here
9 | }
  | - mutable borrow ends here

error: aborting due to previous error
```

Now, same example but enabling NLL. To enable it you just need to use
the NLL feature gate in your crate `#![feature(nll)]`.

```rust
#![feature(nll)]
#![allow(unused_variables)]

fn main() {
    let mut x = 22;

    let p = &mut x;

    println!("{}", x);
}
```
[Run](https://play.rust-lang.org/?gist=446e7952725aa7e0993b4c890bdd8680&version=nightly)

This compiles perfectly fine because the compiler knows that the mutable
borrow of x do not expand until the end of the scope. It just finishes
before using x again, so there’s no conflict there.

Now, a more complex example ...

```rust
use std::collections::HashMap;

fn get_default(map: &mut HashMap, key: usize) -> &mut String {
    match map.get_mut(&key) {
        Some(value) => value,
        None => {
            map.insert(key, "".to_string());
            map.get_mut(&key).unwrap()
        }
    }
}

fn main() {
    let map = &mut HashMap::new();
    map.insert(22, format!("Hello, world"));
    map.insert(44, format!("Goodbye, world"));
    assert_eq!(&*get_default(map, 22), "Hello, world");
    assert_eq!(&*get_default(map, 66), "");
}
```

[Run](https://play.rust-lang.org/?gist=51466a252f37a6853575d260be268d4d&version=nightly)

This example, using the current scoped based lifetime system, doesn’t
compile.
That’s because `get_mut` borrows map from the match until the end of the
scope.
That covers the `None` arm in which we have a mutable borrow, and that’a
not allowed by the compiler.

Here is the compiler error ...

```
error[E0499]: cannot borrow `*map` as mutable more than once at a time
  --> src/main.rs:7:13
   |
4  |     match map.get_mut(&key) {
   |           --- first mutable borrow occurs here
...
7  |             map.insert(key, "".to_string());
   |             ^^^ second mutable borrow occurs here
...
11 | }
   | - first borrow ends here

error[E0499]: cannot borrow `*map` as mutable more than once at a time
  --> src/main.rs:8:13
   |
4  |     match map.get_mut(&key) {
   |           --- first mutable borrow occurs here
...
8  |             map.get_mut(&key).unwrap()
   |             ^^^ second mutable borrow occurs here
...
11 | }
   | - first borrow ends here

error: aborting due to 2 previous errors
```

In order to make this example compile we need some contortions, like ...

```rust
fn get_default(map: &mut HashMap, key: usize) -> &mut String {
    match map.get_mut(&key) {
        Some(value) => return value,
        None => {
        }
    }
    
    map.insert(key, "".to_string());
    map.get_mut(&key).unwrap()
}
```

While this now works, is a bit unfortunate that we need to use this
artificial constructions.

If you now enable NLL by adding `#![feature(nll)]` to the original
example ...

```rust
#![feature(nll)]

use std::collections::HashMap;

fn get_default(map: &mut HashMap, key: usize) -> &mut String {
    match map.get_mut(&key) {
        Some(value) => value,
        None => {
            map.insert(key, "".to_string());
            map.get_mut(&key).unwrap()
        }
    }
}

fn main() {
    let map = &mut HashMap::new();
    map.insert(22, format!("Hello, world"));
    map.insert(44, format!("Goodbye, world"));
    assert_eq!(&*get_default(map, 22), "Hello, world");
    assert_eq!(&*get_default(map, 66), "");
}
```

[Run](https://play.rust-lang.org/?gist=18d0d79621686f58b3ce49bba07dd62d&version=nightly)

Then it perfectly compiles and we don’t have to do the contortions
anymore.

Another interesting thing I’ve helped with is a new way to display
borrowing errors called three point error. For now, you need to
explicitly enable that by using `-Znll-dump-cause`.

So, given the following example with borrowing errors in NLL mode ...

```rust
#![feature(nll)]
#![allow(unused_assignments)]

fn main() {
    let mut x = 22;

    let p = &x;

    x = 33;
    
    println!("{}", p);
}
```

[Run](https://play.rust-lang.org/?gist=99d7dfb9b67412cad86bcea383331538&version=nightly])
(unfortunately you can’t pass `-Znll-dump-cause` in Playpen).

if you try to compile it with `nll-dump-cause` flag enabled, you will
get three point errors which look like ...

```
$ rustc -Znll-dump-cause main.rs
error[E0506]: cannot assign to `x` because it is borrowed
  --> src/main.rs:9:5
   |
7  |     let p = &x;
   |             -- borrow of `x` occurs here
8  | 
9  |     x = 33;
   |     ^^^^^^ assignment to borrowed `x` occurs here
10 |     
11 |     println!("{}", p);
   |                    - borrow later used here

error: aborting due to previous error
```

As you can see it shows where the borrow occurs, where the assignment to
the borrow occurs and where the borrow is later used, which gives you a
very good idea of what the error is about.

There are still some performance issues with this option
(`nll-dump-cause`) so far. The idea is that this thing is going to be
enabled by default once we are able to fix the performance problems
related with it. I will be working on this with the help of Niko, so
stay tuned :).

I’m very excited about NLL as I hope you are. Try to go ahead and test
your code using NLL and report the errors you find. There are already
some issues to fix but things are slowly shaping up.

Lastly, as a bonus paragraph, I’d like to describe a bit my experience
working on this project during the impl period.
First of all, I can’t believe I had the chance to learn directly from
Niko, despite being my first Rust project.
Niko is an admirable professional but more importantly he is super nice
and very accessible.
We spent a lot of time chatting on Gitter, having calls and then 3 days
working during [Rust Belt Rust](https://www.rust-belt-rust.com/).
I also spent some time pairing and sharing thoughts with other
developers, specially with Paul, was a very helpful to have him around.
Well, a paragraph is not enough to describe how grateful I am but I’m
more than happy to share more thoughts if someone is interested. In that
case, just ping me.
