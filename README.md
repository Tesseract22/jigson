# jigson
> :warning: ** This project in still in development and API is not stable. Use it at your own risk.

## A JSON parser implemented with zig using [parser combinator][parser combinator], providing C API (thus comptiable with languag comptiable with C)
This is a toy project for myself to experiment with parser combinator and a more or less functional programming style.
> This is largely inspired by Tsoding's json parser in [Haskell][tsoding yt]

## Installation & Build
`git clone https://github.com/Tesseract22/jigson.git`

`cd jigson`

`zig build`

To run tests,

`zig test src/json.zig`

To read a json file by supplying command line arguments, 

`zig run src/json.zig -- [path/to/json]`

## TODO

- [ ] More comprehensive tests
- [ ] Stable C API
- [ ] Auto generating header with zig `-emit-h` option (currently not working)
- [ ] Benchmarking
- [ ] Support for escape characters






[tsoding yt]: https://www.youtube.com/watch?v=N9RUqGYuGfw
[parser combinator]: https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&cad=rja&uact=8&ved=2ahUKEwjtxIWfoKSAAxVihVYBHWNJDGIQFnoECBMQAQ&url=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FParser_combinator&usg=AOvVaw26qPNFuVgdTXJPwnAXwjpG&opi=89978449
