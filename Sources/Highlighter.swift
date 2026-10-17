import AppKit

// Small single-pass syntax highlighter for fenced code blocks. Not a parser:
// it recognises comments, strings, numbers, keywords, types, calls and
// annotations, which is what makes code readable at a glance.

enum Highlighter {
    enum Token { case keyword, string, comment, number, type, function, meta, added, removed }

    static func color(_ t: Token) -> NSColor {
        let rgb = Palette.rgb
        switch t {
        case .keyword: return Palette.dyn(rgb(207, 34, 46), rgb(255, 123, 114))
        case .string: return Palette.dyn(rgb(10, 48, 105), rgb(165, 214, 255))
        case .comment: return Palette.dyn(rgb(110, 119, 129), rgb(139, 148, 158))
        case .number: return Palette.dyn(rgb(5, 80, 174), rgb(121, 192, 255))
        case .type: return Palette.dyn(rgb(149, 56, 0), rgb(255, 166, 87))
        case .function: return Palette.dyn(rgb(130, 80, 223), rgb(210, 168, 255))
        case .meta: return Palette.dyn(rgb(17, 99, 41), rgb(126, 231, 135))
        case .added: return Palette.dyn(rgb(17, 99, 41), rgb(126, 231, 135))
        case .removed: return Palette.dyn(rgb(130, 7, 30), rgb(255, 161, 152))
        }
    }

    struct Lang {
        var keywords: Set<String> = []
        var builtins: Set<String> = []          // coloured like types
        var line: [String] = []                 // line comment starts
        var block: [(String, String)] = []      // block comment delimiters
        var quotes: [String] = ["\"", "'"]      // longest first
        var multilineQuotes: Set<String> = []   // quotes allowed to span lines
        var capsAreTypes = true
        var meta: Character?                    // @annotation / #directive
        var metaAtLineStart = false
        var variables: Character?               // $var in shells/php/perl
    }

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

    private static let cKeywords = words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL nullptr")
    private static let cppKeywords = cKeywords.union(words("alignas alignof and asm catch class constexpr consteval constinit co_await co_return co_yield concept decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not operator or override final private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw try typeid typename using virtual xor"))
    private static let cFamily = Lang(keywords: cKeywords, line: ["//"], block: [("/*", "*/")], meta: "#", metaAtLineStart: true)

    private static let table: [String: Lang] = {
        var t: [String: Lang] = [:]
        func add(_ names: String, _ l: Lang) { for n in names.split(separator: " ") { t[String(n)] = l } }

        add("c h", cFamily)
        var cpp = cFamily; cpp.keywords = cppKeywords
        add("cpp c++ cc cxx hpp hh", cpp)
        var objc = cFamily; objc.keywords = cKeywords.union(words("@interface @implementation @end @property @protocol @selector self super nil YES NO id instancetype nonatomic strong weak copy readonly"))
        add("objc objective-c objectivec m mm", objc)

        add("swift", Lang(keywords: words("actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in indirect init inout internal is lazy let mutating nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while unowned consuming borrowing"),
                          line: ["//"], block: [("/*", "*/")], quotes: ["\"\"\"", "\""], multilineQuotes: ["\"\"\""], meta: "@"))
        let jvm = "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new null package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false var record sealed permits yield"
        add("java", Lang(keywords: words(jvm), line: ["//"], block: [("/*", "*/")], quotes: ["\"\"\"", "\"", "'"], multilineQuotes: ["\"\"\""], meta: "@"))
        add("kotlin kt kts", Lang(keywords: words("as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg"),
                                       line: ["//"], block: [("/*", "*/")], quotes: ["\"\"\"", "\"", "'"], multilineQuotes: ["\"\"\""], meta: "@"))
        add("scala", Lang(keywords: words("abstract case catch class def do else extends false final finally for forSome if implicit import lazy match new null object override package private protected return sealed super this throw trait try true type val var while with yield given using enum then export"),
                          line: ["//"], block: [("/*", "*/")], quotes: ["\"\"\"", "\"", "'"], multilineQuotes: ["\"\"\""], meta: "@"))
        add("cs csharp c#", Lang(keywords: words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await record init get set yield"),
                                 line: ["//"], block: [("/*", "*/")], meta: "#", metaAtLineStart: true))

        let jsKw = "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield"
        let js = Lang(keywords: words(jsKw), builtins: words("console window document Math JSON Promise Array Object String Number Boolean Map Set Error"),
                      line: ["//"], block: [("/*", "*/")], quotes: ["\"", "'", "`"], multilineQuotes: ["`"], meta: "@")
        add("js javascript jsx mjs cjs node", js)
        var ts = js; ts.keywords = words(jsKw + " abstract any as asserts boolean declare enum implements infer interface is keyof namespace never number private protected public readonly satisfies string symbol type unique unknown override")
        add("ts typescript tsx mts", ts)
        add("json jsonc json5", Lang(keywords: words("true false null"), line: ["//"], block: [("/*", "*/")], quotes: ["\""], capsAreTypes: false))

        add("go golang", Lang(keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota"),
                              builtins: words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any append cap close copy delete len make new panic print println recover"),
                              line: ["//"], block: [("/*", "*/")], quotes: ["\"", "'", "`"], multilineQuotes: ["`"]))
        add("rust rs", Lang(keywords: words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
                            builtins: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Some None Ok Err Box"),
                            line: ["//"], block: [("/*", "*/")], quotes: ["\""], meta: "#"))
        add("zig", Lang(keywords: words("const var fn pub return if else while for switch break continue defer errdefer try catch struct enum union error comptime inline export extern test true false null undefined orelse and or"),
                        line: ["//"], quotes: ["\"", "'"], meta: "@"))

        add("python py python3 py3", Lang(keywords: words("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield match case self"),
                                          builtins: words("print len range int str float list dict set tuple bool open type isinstance super enumerate zip map filter sorted min max sum abs any all"),
                                          line: ["#"], quotes: ["\"\"\"", "'''", "\"", "'"], multilineQuotes: ["\"\"\"", "'''"], meta: "@"))
        add("ruby rb", Lang(keywords: words("alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader puts"),
                            line: ["#"], block: [("=begin", "=end")], variables: "@"))
        add("lua", Lang(keywords: words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"),
                        line: ["--"], block: [("--[[", "]]")], quotes: ["\"", "'"]))
        add("php", Lang(keywords: words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include instanceof insteadof interface isset list match namespace new or print private protected public readonly require return static switch throw trait try unset use var while xor yield true false null"),
                        line: ["//", "#"], block: [("/*", "*/")], variables: "$"))
        add("perl pl", Lang(keywords: words("my our local sub if elsif else unless while until for foreach return last next redo use require package print undef"),
                            line: ["#"], variables: "$"))
        let sh = Lang(keywords: words("if then else elif fi case esac for while until do done in function return local export readonly declare unset shift break continue exit source alias echo cd set eval exec trap"),
                      line: ["#"], quotes: ["\"", "'"], multilineQuotes: ["\"", "'"], capsAreTypes: false, variables: "$")
        add("sh bash zsh shell fish console shellscript ksh", sh)
        add("powershell ps1 pwsh", Lang(keywords: words("begin break catch class continue data do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while"),
                                        line: ["#"], block: [("<#", "#>")], capsAreTypes: false, variables: "$"))
        add("dockerfile docker", Lang(keywords: words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS"),
                                      line: ["#"], capsAreTypes: false, variables: "$"))
        add("makefile make mk", Lang(keywords: words("ifeq ifneq ifdef ifndef else endif include define endef export override .PHONY"), line: ["#"], capsAreTypes: false, variables: "$"))

        var sql = Lang(line: ["--"], block: [("/*", "*/")], quotes: ["'", "\""], capsAreTypes: false)
        let sqlKw = "select from where and or not insert into values update set delete create table drop alter add column index view join inner left right outer full on as group by order having limit offset distinct union all case when then else end is null like in between exists primary key foreign references default unique check constraint returning with begin commit rollback transaction grant revoke cascade asc desc count sum avg min max int integer varchar text boolean date timestamp serial"
        sql.keywords = words(sqlKw).union(words(sqlKw.uppercased()))
        add("sql psql mysql postgres postgresql sqlite plsql", sql)

        add("haskell hs", Lang(keywords: words("case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where qualified as hiding"),
                               line: ["--"], block: [("{-", "-}")], quotes: ["\""]))
        add("elixir ex exs", Lang(keywords: words("def defp defmodule defstruct defmacro do end if else unless case cond fn when with for receive try catch rescue after raise import alias require use true false nil and or not in"),
                                  line: ["#"], quotes: ["\"\"\"", "\"", "'"], multilineQuotes: ["\"\"\""], meta: "@"))
        add("erlang erl", Lang(keywords: words("after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse receive rem try when xor"), line: ["%"], quotes: ["\""], meta: "-"))
        add("clojure clj cljs edn lisp scheme el elisp racket", Lang(keywords: words("def defn defmacro fn let if do when cond loop recur ns require import quote define lambda set! begin and or not nil true false"),
                                                                    line: [";"], quotes: ["\""], capsAreTypes: false))
        add("ocaml ml fsharp fs", Lang(keywords: words("let rec in fun function match with type of module open if then else begin end val mutable and or not true false"),
                                       line: ["//"], block: [("(*", "*)")], quotes: ["\""]))
        add("dart", Lang(keywords: words("abstract as assert async await break case catch class const continue default do dynamic else enum export extends extension external factory false final finally for get if implements import in is late library mixin new null on operator part required rethrow return set static super switch sync this throw true try typedef var void while with yield"),
                         line: ["//"], block: [("/*", "*/")], meta: "@"))
        add("r", Lang(keywords: words("if else repeat while function for in next break TRUE FALSE NULL Inf NaN NA library return"), line: ["#"], capsAreTypes: false))
        add("julia jl", Lang(keywords: words("function end if else elseif for while return module using import struct mutable begin let local global const true false nothing do try catch finally macro quote in"),
                             line: ["#"], block: [("#=", "=#")], quotes: ["\"\"\"", "\""], multilineQuotes: ["\"\"\""], meta: "@"))
        add("vim viml vimscript", Lang(keywords: words("let set if else elseif endif for endfor while endwhile function endfunction call return map nnoremap inoremap vnoremap noremap autocmd augroup command"),
                                       line: ["\""], quotes: ["'"], capsAreTypes: false))

        add("css scss sass less", Lang(keywords: words("important media import include mixin extend if else each for return keyframes font-face supports"),
                                       line: ["//"], block: [("/*", "*/")], capsAreTypes: false, meta: "@", variables: "$"))
        add("yaml yml", Lang(keywords: words("true false null yes no on off ~"), line: ["#"], capsAreTypes: false))
        add("toml ini conf cfg properties", Lang(keywords: words("true false"), line: ["#", ";"], quotes: ["\"\"\"", "\"", "'"], multilineQuotes: ["\"\"\""], capsAreTypes: false))
        add("graphql gql", Lang(keywords: words("query mutation subscription fragment on type interface union enum input scalar schema extend directive implements true false null"),
                                line: ["#"], quotes: ["\"\"\"", "\""], multilineQuotes: ["\"\"\""], meta: "@", variables: "$"))
        add("protobuf proto", Lang(keywords: words("syntax package import option message enum service rpc returns repeated optional required oneof map reserved stream true false"),
                                   builtins: words("double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 bool string bytes"), line: ["//"], block: [("/*", "*/")]))
        add("nix", Lang(keywords: words("let in with rec inherit if then else assert import true false null"), line: ["#"], block: [("/*", "*/")], quotes: ["''", "\""], multilineQuotes: ["''"], capsAreTypes: false))
        add("terraform hcl tf", Lang(keywords: words("resource data variable output module provider locals terraform for_each count depends_on true false null"), line: ["#", "//"], block: [("/*", "*/")], capsAreTypes: false))
        return t
    }()

    static func highlight(_ code: String, lang hint: String?, font: NSFont) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(string: code, attributes: [.font: font, .foregroundColor: Palette.text])
        guard let hint = hint?.lowercased().split(separator: " ").first.map(String.init), !hint.isEmpty else { return out }
        let s = code as NSString
        let paint: (NSRange, Token) -> Void = { r, t in
            out.addAttribute(.foregroundColor, value: color(t), range: r)
            if t == .comment {
                out.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: r)
            }
        }
        switch hint {
        case "diff", "patch": diff(s, paint)
        case "html", "xml", "svg", "xhtml", "plist", "vue", "svelte": markup(s, paint)
        default:
            if let l = table[hint] { scan(s, l, paint) }
        }
        return out
    }

    private static func diff(_ s: NSString, _ paint: (NSRange, Token) -> Void) {
        var i = 0
        while i < s.length {
            let r = s.lineRange(for: NSRange(location: i, length: 0))
            let line = s.substring(with: r)
            if line.hasPrefix("+++") || line.hasPrefix("---") { paint(r, .keyword) }
            else if line.hasPrefix("+") { paint(r, .added) }
            else if line.hasPrefix("-") { paint(r, .removed) }
            else if line.hasPrefix("@@") { paint(r, .function) }
            i = NSMaxRange(r)
        }
    }

    private static let markupRules: [(NSRegularExpression, Token, Int)] = [
        (try! NSRegularExpression(pattern: "</?([A-Za-z][\\w:.-]*)"), .keyword, 1),
        (try! NSRegularExpression(pattern: "\\s([A-Za-z_:][\\w:.-]*)\\s*="), .type, 1),
        (try! NSRegularExpression(pattern: "\"[^\"]*\"|'[^']*'"), .string, 0),
        (try! NSRegularExpression(pattern: "&[#\\w]+;"), .number, 0),
        (try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|<!\\[CDATA\\[[\\s\\S]*?\\]\\]>|<![^>]*>|<\\?[\\s\\S]*?\\?>"), .comment, 0),
    ]

    private static func markup(_ s: NSString, _ paint: (NSRange, Token) -> Void) {
        let all = NSRange(location: 0, length: s.length)
        for (re, tok, group) in markupRules {
            for m in re.matches(in: s as String, range: all) { paint(m.range(at: group), tok) }
        }
    }

    private static func isIdentStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }
    private static func isIdent(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static func scan(_ s: NSString, _ l: Lang, _ paint: (NSRange, Token) -> Void) {
        let n = s.length
        var buf = [unichar](repeating: 0, count: n)
        s.getCharacters(&buf, range: NSRange(location: 0, length: n))
        func at(_ i: Int, _ p: String) -> Bool {
            var j = i
            for u in p.utf16 {
                if j >= n || buf[j] != u { return false }
                j += 1
            }
            return true
        }
        let metaU = l.meta.flatMap { $0.utf16.first }
        let varU = l.variables.flatMap { $0.utf16.first }
        var lineStart = true
        var i = 0
        outer: while i < n {
            let c = buf[i]
            if c == 10 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 { i += 1; continue }
            let wasLineStart = lineStart
            lineStart = false

            for (open, close) in l.block where at(i, open) {
                var j = i + open.utf16.count
                while j < n && !at(j, close) { j += 1 }
                j = min(n, j + close.utf16.count)
                paint(NSRange(location: i, length: j - i), .comment)
                i = j
                continue outer
            }
            for p in l.line where at(i, p) {
                var j = i
                while j < n && buf[j] != 10 { j += 1 }
                paint(NSRange(location: i, length: j - i), .comment)
                i = j
                continue outer
            }
            for q in l.quotes where at(i, q) {
                let ql = q.utf16.count
                let multi = l.multilineQuotes.contains(q)
                var j = i + ql
                while j < n {
                    if buf[j] == 92 { j += 2; continue }              // backslash escape
                    if at(j, q) { j += ql; break }
                    if buf[j] == 10 && !multi { break }
                    j += 1
                }
                j = min(j, n)
                paint(NSRange(location: i, length: j - i), .string)
                i = j
                continue outer
            }
            if let m = metaU, c == m, !l.metaAtLineStart || wasLineStart {
                var j = i + 1
                while j < n && (isIdent(buf[j]) || buf[j] == 46) { j += 1 }
                if j > i + 1 || l.metaAtLineStart {
                    if l.metaAtLineStart { while j < n && buf[j] != 10 { j += 1 } }
                    paint(NSRange(location: i, length: j - i), .meta)
                    i = j
                    continue
                }
            }
            if let v = varU, c == v {
                var j = i + 1
                if j < n && buf[j] == 123 {                          // ${...}
                    while j < n && buf[j] != 125 && buf[j] != 10 { j += 1 }
                    j = min(n, j + 1)
                } else {
                    while j < n && (isIdent(buf[j]) || (j == i + 1 && "@#?*!$-".utf16.contains(buf[j]))) { j += 1 }
                }
                if j > i + 1 {
                    paint(NSRange(location: i, length: j - i), .type)
                    i = j
                    continue
                }
            }
            if isDigit(c) || (c == 46 && i + 1 < n && isDigit(buf[i + 1])) {
                var j = i + 1
                while j < n && (isIdent(buf[j]) || buf[j] == 46) {
                    if buf[j] == 46 && j + 1 < n && buf[j + 1] == 46 { break }  // ranges: 0..<n
                    j += 1
                }
                paint(NSRange(location: i, length: j - i), .number)
                i = j
                continue
            }
            if isIdentStart(c) {
                var j = i + 1
                while j < n && isIdent(buf[j]) { j += 1 }
                // allow keywords like `defined?` / `set!` / `@end`
                if j < n && (buf[j] == 63 || buf[j] == 33), l.keywords.contains(String(utf16CodeUnits: Array(buf[i...j]), count: j - i + 1)) { j += 1 }
                let w = String(utf16CodeUnits: Array(buf[i..<j]), count: j - i)
                var k = j
                while k < n && buf[k] == 32 { k += 1 }
                if l.keywords.contains(w) {
                    paint(NSRange(location: i, length: j - i), .keyword)
                } else if l.builtins.contains(w) || (l.capsAreTypes && c >= 65 && c <= 90) {
                    paint(NSRange(location: i, length: j - i), .type)
                } else if k < n && buf[k] == 40 {
                    paint(NSRange(location: i, length: j - i), .function)
                }
                i = j
                continue
            }
            i += 1
        }
    }
}
