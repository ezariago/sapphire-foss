import Foundation
let cases: [(String, String)] = [
    ("https://example.com/a?utm_source=x&a=%2f&fbclid=y&b=+", "https://example.com/a?a=%2f&b=+"),
    ("https://example.com/?UTM_campaign=x#section", "https://example.com/#section"),
    ("https://example.com/?x=1&x=2&utm_medium=y", "https://example.com/?x=1&x=2"),
    ("https://example.com/?%75tm_source=x&foo=bar", "https://example.com/?foo=bar"),
    ("https://example.com/?utm_source=a&X-Amz-Signature=abc", "https://example.com/?utm_source=a&X-Amz-Signature=abc"),
    ("https://example.com/?sig=abc&gclid=x", "https://example.com/?sig=abc&gclid=x"),
    ("some text https://example.com/?gclid=x", "some text https://example.com/?gclid=x"),
    ("file:///tmp/test?gclid=x", "file:///tmp/test?gclid=x"),
    ("https://example.com/?q=a%26b%3Dc&gclid=x", "https://example.com/?q=a%26b%3Dc"),
    ("https://example.com/path?keep=&utm_medium=x", "https://example.com/path?keep=")
]
for (input, output) in cases {
    let actual = ClipboardURLCleaner.clean(input)
    assert(actual == output, "\(input) became \(actual), expected \(output)")
    assert(ClipboardURLCleaner.clean(actual) == actual)
}
assert(ClipboardURLCleaner.clean("https://example.com/?campaign=x&a=1", customParameters: ["campaign"]) == "https://example.com/?a=1")
var expiry = ClipboardExpiryPolicy(changeCount: 10, now: 100)
assert(!expiry.shouldClear(now: 129.9, interval: 30))
assert(expiry.shouldClear(now: 130, interval: 30))
expiry.observe(11, now: 129)
assert(!expiry.shouldClear(now: 130, interval: 30))
expiry.observe(11, now: 150)
assert(expiry.shouldClear(now: 159, interval: 30))
assert(!expiry.shouldClear(now: 99, interval: 30))
assert(!expiry.shouldClear(now: 1000, interval: 0))
assert(!expiry.shouldClear(now: 1000, interval: .nan))
print("Passed URL tracking removal, signed URL/encoding preservation, idempotence and clipboard expiry checks.")
