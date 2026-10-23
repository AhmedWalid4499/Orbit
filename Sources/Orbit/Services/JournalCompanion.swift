import Foundation
import SwiftData

struct JournalTurn: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String          // "user" | "assistant"
    var text: String          // what the UI shows
    var raw: Data? = nil      // assistant content blocks, replayed unchanged
    var hidden = false        // e.g. the opening nudge
    var at = Date.now
}

/// The conversation stored on a journal note. The system prompt is frozen when the chat starts,
/// so every later request is a strict append to the same history.
struct JournalChat: Codable, Equatable {
    var system: String
    var turns: [JournalTurn] = []
}

extension Note {
    var chat: JournalChat? {
        get { chatData.flatMap { try? JSONDecoder().decode(JournalChat.self, from: $0) } }
        set { chatData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

enum Mood {
    static let faces = ["", "😞", "😕", "😐", "🙂", "😄"]
    static let words = ["", "Rough", "Low", "Okay", "Good", "Great"]
}

/// Claude as a journaling companion: asks about mood and the day, then writes the entry.
@MainActor
enum JournalCompanion {
    private struct MoodGuess: Decodable { let mood: Int }
    private struct WriteUp: Decodable { let entry: String; let mood: Int }

    static func systemPrompt(context: ModelContext, apple: AppleSync) -> String {
        let name = (Platform.userName)
            .split(separator: " ").first.map(String.init) ?? "there"
        return """
        You are \(AssistantName.current), a gentle, warm journaling companion inside \(name)'s personal organizer app. You help \(name) unwind and reflect on today through a calm, unhurried conversation, so their journal entry almost writes itself.

        Tone:
        - Soft and kind, like a close friend checking in at the end of the day. Never clinical, never a coach, never a therapist.
        - Short. Usually one or two sentences, and never more than one question per message.
        - Start with a little warmth before you ask anything. If they share something hard, acknowledge it gently first; don't rush to the next question or try to fix it.
        - If you have two separate thoughts (a reflection and then a question), put a blank line between them.
        - Plain text only. No lists, no headings, no markdown, no emoji unless they use them first.

        Flow:
        - Open by asking how they're feeling today.
        - Then, at their pace, ask about what they did, a moment that stood out, and anything on their mind for tomorrow.
        - Use the day's data below to make questions specific ("How did the budget review go?"), but never assume something happened just because it was planned.
        - After about 4-6 exchanges, or when they seem done, mention softly that they can tap "Write my entry" to turn the chat into today's journal.
        - If they mention feeling unsafe or in crisis, respond with care and encourage reaching out to someone they trust or local emergency services.

        Today's data from the app:
        \(AIAssistant.snapshot(context: context, apple: apple))
        """
    }

    /// Starts the check-in: Claude opens with a question about mood.
    static func start(note: Note, context: ModelContext, apple: AppleSync, onText: @escaping @MainActor (String) -> Void) async throws {
        var chat = note.chat ?? JournalChat(system: systemPrompt(context: context, apple: apple))
        if chat.turns.isEmpty {
            chat.turns.append(JournalTurn(role: "user", text: "I just opened today's journal.", hidden: true))
            note.chat = chat
        }
        try await reply(note: note, onText: onText)
    }

    static func send(_ text: String, note: Note, context: ModelContext, apple: AppleSync,
                     onText: @escaping @MainActor (String) -> Void) async throws {
        var chat = note.chat ?? JournalChat(system: systemPrompt(context: context, apple: apple))
        chat.turns.append(JournalTurn(role: "user", text: text))
        note.chat = chat
        Task { await updateMood(note: note) }
        try await reply(note: note, onText: onText)
    }

    /// Streams Claude's next message. On failure the user's turn stays, so a retry continues cleanly.
    static func reply(note: Note, onText: @escaping @MainActor (String) -> Void) async throws {
        guard let client = ClaudeClient() else { throw ClaudeClient.Failure.noKey }
        guard var chat = note.chat, chat.turns.last?.role == "user" else { return }

        let messages: [[String: Any]] = chat.turns.map { turn in
            if turn.role == "assistant", let raw = turn.raw,
               let blocks = try? JSONSerialization.jsonObject(with: raw) {
                return ["role": "assistant", "content": blocks]
            }
            return ["role": turn.role, "content": turn.text]
        }
        let result = try await client.stream(system: chat.system, messages: messages, effort: "low", onText: onText)
        chat.turns.append(JournalTurn(role: "assistant", text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                      raw: result.rawContent))
        note.chat = chat
        note.updatedAt = .now
    }

    /// Quietly estimates today's mood from what the user has said (never overrides a mood they picked).
    static func updateMood(note: Note) async {
        guard !note.moodSetByUser, let client = ClaudeClient(), let chat = note.chat else { return }
        let said = chat.turns.filter { $0.role == "user" && !$0.hidden }.map(\.text).joined(separator: "\n")
        guard !said.isEmpty else { return }
        let guess = try? await client.structured(MoodGuess.self,
            system: "Estimate the writer's mood today from 1 (rough) to 5 (great), from their own words only. 0 if they haven't said how they feel.",
            user: said,
            schema: ["type": "object", "properties": ["mood": ["type": "integer"]], "required": ["mood"], "additionalProperties": false],
            effort: "low", maxTokens: 2000)
        if let m = guess?.mood, (1...5).contains(m), !note.moodSetByUser { note.mood = m }
    }

    /// Writes one journal entry from what's already written plus the conversation, replacing the body.
    /// Returns the previous body so the caller can offer undo.
    static func writeEntry(note: Note) async throws -> String {
        guard let client = ClaudeClient() else { throw ClaudeClient.Failure.noKey }
        guard let chat = note.chat else { return note.body }
        let transcript = chat.turns.filter { !$0.hidden }
            .map { "\($0.role == "user" ? "Me" : "Companion"): \($0.text)" }
            .joined(separator: "\n")
        let system = """
        Write today's journal entry in the first person, as the user ("Me").
        You get what they've already written in their journal (may be empty) and a conversation with their companion.
        Produce ONE cohesive entry that includes everything from both without repeating anything: keep their own sentences where you can, fix only obvious typos, and fold in what they said in the chat.
        Use only what the user actually wrote or said; don't add events or feelings they didn't express.
        2-4 short paragraphs of plain text, no headings, no markdown, no date line.
        mood: 1 (rough) to 5 (great) from what they said, or 0 if unclear.
        """
        let input = "ALREADY WRITTEN:\n\(note.body.isEmpty ? "(nothing yet)" : note.body)\n\nCONVERSATION:\n\(transcript)"
        let result = try await client.structured(WriteUp.self, system: system, user: input, schema: [
            "type": "object",
            "properties": ["entry": ["type": "string"], "mood": ["type": "integer"]],
            "required": ["entry", "mood"],
            "additionalProperties": false,
        ], effort: "medium")
        let previous = note.body
        note.body = result.entry
        if (1...5).contains(result.mood), !note.moodSetByUser { note.mood = result.mood }
        note.updatedAt = .now
        return previous
    }
}
