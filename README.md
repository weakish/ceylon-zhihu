A ceylon client to zhihu.com API.

Currently it supports readonly APIs of zhuanlan.zhihu.com.

Usage
-----

See <https://weakish.github.io/ceylon-zhihu/api/>

Install
-------

### Dependencies

- Java 7+
- wget

### As a library

#### With Java

Download the jar file at [Releases] page and put it in `classpath`.

[Releases]: https://github.com/weakish/ceylon-zhihu/releases

#### With Ceylon

Download the car file at [Releases] page and put it in ceylon module repository.

### As a command line tool

Download the jar file at [Releases] page and rename it to `zhihu.jar`
or anything you like.

Development
-----------

You need Ceylon, unless you want to mess up with decompiled Java code.

If you need to modify the source, clone this repository with git.

If you do not want to use git,
download the tarball, zip or car file at [Releases].

### Makefile

There is a `Makefile` in the repository, compatible with both BSD and GNU `make`.

#### Test

```sh
make test
```

#### Compile

```
make build
```

#### Package

Packages to a fat jar (requires `ceylon` 1.2.3 snapshot)

```sh
make jar
```

### Contribute

See `CONTRIBUTING.md` in the repository.

License
-------

0BSD

Todo
----

### Content Image named with full path

e.g. `hosts_dir_filename.png`.

`wget` seems have option for this.

### Incremental backup.

e.g. Etag
