import Foundation

@main
struct ArticlePracticeChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: "Resources/ArticlePractice/article-data.json")
        let document = try ArticlePracticeDocument.load(from: url)
        precondition(document.treeParagraphs.count == 24)
        precondition(document.coverage.bodyWords == 934)
        let prototype = try Data(contentsOf: URL(fileURLWithPath: "prototypes/topic-practice/article-data.json"))
        let bundled = try Data(contentsOf: url)
        precondition(prototype == bundled, "Bundled article must match the verified full prototype")
        var object = try JSONSerialization.jsonObject(with: prototype) as! [String: Any]
        var groups = object["groups"] as! [[String: Any]]
        var evidence = groups[0]["evidence"] as! [[String: Any]]
        evidence.removeLast()
        groups[0]["evidence"] = evidence
        object["groups"] = groups
        let missing = try JSONDecoder().decode(ArticlePracticeDocument.self, from: JSONSerialization.data(withJSONObject: object))
        do {
            try missing.validate()
            preconditionFailure("An incomplete article must not be shown as complete")
        } catch ArticlePracticeError.invalidCoverage { }
        precondition(ArticlePracticeDocument.webURL("file:///tmp/example") == nil)
        precondition(ArticlePracticeDocument.webURL("javascript:alert(1)") == nil)
        print("ArticlePracticeChecks passed: 24 complete paragraphs, exact bundle parity, incomplete articles rejected")
    }
}
