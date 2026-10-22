/// Decodes one array member independently so malformed user-edited entries can be dropped.
struct LossyDecoded<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}
