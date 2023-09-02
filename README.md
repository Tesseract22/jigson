# jigson
> :warning: ** This project in still in development and API is not stable. Use it at your own risk.

## A JSON parser implemented with zig using [parser combinator][parser combinator] with C API
This is a toy project for myself to experiment with parser combinator and a more or less functional programming style.
> This is largely inspired by [Tsoding's][tsoding yt] [json parser][tsoding json repo] in `Haskell`

Under the hood, we use zig's `comptime` feature to generate parser combinator with zero runtime cost.
## Installation & Build
`git clone https://github.com/Tesseract22/jigson.git`

`cd jigson`

`zig build`, which would generate:

`zig-out/lib/libjson.so`
`zig-out/bin/json`, a minimal working example for reading a file and parsing it into json
`zig-out/bin/c_example`, a minimal working example for using the `src/c/json.h` header and linking with `libjson.so` in `C`

To run tests,

`zig test src/json.zig`

To read a json file by supplying command line arguments, 

`zig run src/json.zig -- [path/to/json]`

## TODO

- [ ] Provide line and column number `xx:yy` when encountering an error
- [x] More comprehensive tests
- [x] Stable C API
- [ ] Auto generating header with zig `-emit-h` option (currently manually created)
- [ ] Benchmarking
- [ ] Support for escape characters (e.g., `'\"'` in string)





[tsoding json repo]: https://github.com/tsoding/haskell-json/blob/bafd97d96b792edd3e170525a7944b9f01de7e34/Main.hs
[tsoding yt]: https://www.youtube.com/watch?v=N9RUqGYuGfw
[parser combinator]: https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwjtxIWfoKSAAxVihVYBHWNJDGIQFnoECBMQAQ&url=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FParser_combinator&usg=AOvVaw26qPNFuVgdTXJPwnAXwjpG&opi=89978449
