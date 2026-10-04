import Foundation

/// 「绩点计算」里的一门课程记录。学分与成绩以输入原文存储，
/// 解析失败（空、非数字、越界）时不参与汇总，避免非法输入打断录入。
struct GPACourse: Identifiable, Hashable, Codable {
    var id = UUID()
    var name = ""
    var creditsText = ""
    var scoreText = ""

    /// 解析后的学分，大于 0 才有效。
    var credits: Double? {
        guard let value = Double(creditsText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    /// 解析后的百分制成绩，0–100 才有效。
    var score: Double? {
        guard let value = Double(scoreText.trimmingCharacters(in: .whitespaces)), (0...100).contains(value) else { return nil }
        return value
    }

    /// 按五分制换算后的单课程绩点，成绩无效时为 nil。
    var gradePoint: Double? {
        score.map(GPAGradingScale.point(for:))
    }

    /// 输入了可解析但越界的成绩（如 108），用于行内报错。
    var hasScoreError: Bool {
        guard !scoreText.isEmpty, let value = Double(scoreText.trimmingCharacters(in: .whitespaces)) else { return false }
        return !(0...100).contains(value)
    }

    /// 输入了可解析但不合法的学分（如 0 或负数），用于行内报错。
    var hasCreditsError: Bool {
        guard !creditsText.isEmpty, let value = Double(creditsText.trimmingCharacters(in: .whitespaces)) else { return false }
        return value <= 0
    }
}

/// 五分制绩点换算。规则与 app 内手册条目「绩点计算规则」（MockData h2e2）一致：
/// 90–100 为 5.0，此后每 5 分一档递减 0.5，60 以下为 0。
/// 未检索到东南大学官方公开的换算文件，页面脚注中已向用户标注该来源假设。
enum GPAGradingScale {
    static func point(for score: Double) -> Double {
        switch score {
        case 90...100: return 5.0
        case 85..<90: return 4.5
        case 80..<85: return 4.0
        case 75..<80: return 3.5
        case 70..<75: return 3.0
        case 65..<70: return 2.5
        case 60..<65: return 2.0
        default: return 0
        }
    }
}

/// 汇总结果：加权平均绩点 = Σ学分×绩点 / Σ学分，加权平均分同理。无有效行时各项为 0。
struct GPASummary: Equatable {
    var totalCredits = 0.0
    var averageScore = 0.0
    var gradePoint = 0.0
    var countedCourses = 0

    var gradePointText: String { String(format: "%.2f", gradePoint) }
    var averageScoreText: String { String(format: "%.1f", averageScore) }
    var totalCreditsText: String { String(format: "%g", totalCredits) }
}

/// 课程行的本地持久化（UserDefaults + Codable）。只服务「绩点计算」，
/// 与全局 UserProfile 解耦，因此放在 Tools 目录内。
@Observable
final class GPACalculatorStore {
    private static let storageKey = "tools.gpa-calculator.courses"

    var courses: [GPACourse] {
        didSet { persist() }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        courses = data.flatMap { try? JSONDecoder().decode([GPACourse].self, from: $0) } ?? []
    }

    func addCourse() {
        courses.append(GPACourse())
    }

    var summary: GPASummary {
        var summary = GPASummary()
        var pointSum = 0.0
        var scoreSum = 0.0
        for course in courses {
            guard let credits = course.credits, let score = course.score else { continue }
            summary.totalCredits += credits
            pointSum += credits * GPAGradingScale.point(for: score)
            scoreSum += credits * score
            summary.countedCourses += 1
        }
        if summary.totalCredits > 0 {
            summary.gradePoint = pointSum / summary.totalCredits
            summary.averageScore = scoreSum / summary.totalCredits
        }
        return summary
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
