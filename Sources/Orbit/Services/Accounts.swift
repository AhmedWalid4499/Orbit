import Foundation
import SwiftData

/// Works out which bank account or card a payment went through, from the bank text (sender + "ending 1234") or the
/// Wallet card's name, adding the account the first time it's seen, and keeps the balance the text mentions.
@MainActor
enum Accounts {
    /// Card gradients, in the order new accounts get them.
    static let palettes = 6

    /// The account for a bank text: the bank from the sender (or the text), the card or account from its last 4 digits.
    static func forMessage(_ text: String, sender: String, context: ModelContext) -> BankAccount? {
        let bank = bankName(sender: sender) ?? bankName(sender: text) ?? ""
        let digits = last4(in: text)
        guard !bank.isEmpty || !digits.isEmpty else { return nil }
        let wallet = ["vodafone cash", "instapay", "fawry", "etisalat cash", "orange cash", "we pay"].contains { text.lowercased().contains($0) && bank.isEmpty }
        return find(bank: bank.isEmpty ? (wallet ? "Wallet" : "Card") : bank, last4: digits,
                    kind: text.lowercased().contains("account") || text.contains("حساب") ? "account" : (wallet ? "wallet" : "card"), context: context)
    }

    /// The account for an Apple Pay tap: Wallet passes the card's name, e.g. "CIB Visa" or "NBE ••1234".
    static func forWalletCard(_ card: String, context: ModelContext) -> BankAccount? {
        let name = card.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let digits = last4(in: name)
        let bank = bankName(sender: name) ?? name.replacingOccurrences(of: #"[•*#]+\s*\d{4}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return find(bank: bank, last4: digits, kind: "card", context: context)
    }

    /// Finds the account (same last 4 digits, or the same bank when no digits are known), or adds it.
    static func find(bank: String, last4: String, kind: String, context: ModelContext) -> BankAccount {
        let all = (try? context.fetch(FetchDescriptor<BankAccount>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let b = bank.lowercased()
        // The last 4 digits identify the card even after you rename it; the bank name only breaks ties.
        let sameDigits = last4.isEmpty ? [] : all.filter { $0.last4 == last4 }
        if let hit = sameDigits.first(where: { b.isEmpty || $0.name.lowercased() == b || $0.name == "Card" }) ?? sameDigits.first {
            if hit.name == "Card", !bank.isEmpty, bank != "Card" { hit.name = bank }
            return hit
        }
        if last4.isEmpty, let hit = all.first(where: { $0.name.lowercased() == b }) { return hit }
        let a = BankAccount(name: bank.isEmpty ? "Card" : bank, last4: last4, kind: kind)
        a.uuid = UUID().uuidString.lowercased()
        a.colorIndex = all.count % palettes
        context.insert(a)
        return a
    }

    /// Short bank name from a text's sender ("CIB", "NBE", "Banque Misr"), or nil.
    static func bankName(sender: String) -> String? {
        let s = sender.lowercased()
        guard !s.isEmpty else { return nil }
        for bank in EgyptBanks.all where bank.senders.contains(where: { s.contains($0.lowercased()) }) {
            // "National Bank of Egypt (NBE)" → "NBE"
            if let open = bank.name.firstIndex(of: "("), let close = bank.name.firstIndex(of: ")"), open < close {
                return String(bank.name[bank.name.index(after: open)..<close])
            }
            return bank.name
        }
        return nil
    }

    /// "ending 1234", "**5678", "#1234", "xxxx1234", "المنتهية بـ 4455".
    static func last4(in text: String) -> String {
        let patterns = [#"(?i)(?:ending(?: with)?|ends? (?:in|with)|card no\.?|a/c|acct|account)\s*(?:no\.?\s*)?[#*xX•.\s]*(\d{4})\b"#,
                        #"[*xX•#]{2,}\s*(\d{4})\b"#, #"المنتهية\s*(?:بـ|ب)?\s*(\d{4})"#, #"(?:رقم|بطاقة)[^\d]{0,12}(\d{4})\b"#]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(m.range(at: 1), in: text) { return String(text[range]) }
        }
        return ""
    }

    /// The balance or credit left a text mentions ("Balance: EGP 8,400.00", "Available limit EGP 45,210.50", "الرصيد 1200").
    static func balance(in text: String) -> Double? {
        let p = #"(?i)(?:available\s+(?:balance|limit|credit)|balance|bal\.?|avl\.?\s*bal|الرصيد(?:\s+المتاح)?|رصيدكم|الحد المتاح)[^\d]{0,24}([\d٠-٩][\d٠-٩,٬]*(?:[.٫][\d٠-٩]+)?)"#
        guard let r = try? NSRegularExpression(pattern: p),
              let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range(at: 1), in: text) else { return nil }
        return StatementImport.number(String(text[range])).map(abs)
    }

    /// Spending and money in through one account in a stretch of time.
    static func totals(_ account: BankAccount, _ txns: [Transaction], in p: DateInterval) -> (spent: Double, income: Double) {
        let mine = txns.filter { $0.account == account.uuid && $0.date >= p.start && $0.date < p.end }
        return (-mine.filter(\.isExpense).reduce(0) { $0 + $1.amount }, mine.filter { !$0.isExpense }.reduce(0) { $0 + $1.amount })
    }
}
