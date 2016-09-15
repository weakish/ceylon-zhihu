# Compatible with GNU make and BSD make.

build:
	@ant compile
# `process.exit` returns `Nothing`.

doc:
	@ant doc

run-test:
	@ceylon test `ceylon version`

test: build run-test

fat-jar:
	@ceylon fat-jar `ceylon version`

jar: build fat-jar
