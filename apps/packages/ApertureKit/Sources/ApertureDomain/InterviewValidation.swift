import Foundation

/// The outcome of validating a user's interview answer against a specific field.
public enum InterviewValidationResult: Sendable, Hashable {
    case valid(normalizedValue: String)
    case invalid(rejectionPrompt: String, rawCandidate: String?)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public var normalizedValue: String? {
        if case let .valid(value) = self { return value }
        return nil
    }

    public var rejectionPrompt: String? {
        if case let .invalid(prompt, _) = self { return prompt }
        return nil
    }
}

/// Intelligent extractor and strict validator for conversational interview answers.
///
/// Ensures invalid inputs (such as impossible calendar dates like 1/32/2007,
/// empty strings, gibberish, or malformed values) are rejected with clear,
/// conversational explanations, and valid answers are normalized to canonical formats.
public enum InterviewEntityExtractor: Sendable {

    public static func validate(
        answer: String,
        for question: InterviewQuestion,
        locale: String = Locale.current.identifier
    ) -> InterviewValidationResult {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let isSpanish = locale.lowercased().hasPrefix("es")
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "Por favor ingrese una respuesta para continuar."
                    : "Please provide an answer to continue.",
                rawCandidate: nil
            )
        }

        let isSpanish = locale.lowercased().hasPrefix("es") || question.prompt.contains("¿")

        // 1. Choice input kind
        if question.inputKind == .choice, let choices = question.choices, !choices.isEmpty {
            return validateChoice(input: trimmed, choices: choices, isSpanish: isSpanish)
        }

        // 2. Yes/No input kind
        if question.inputKind == .yesNo {
            return validateYesNo(input: trimmed, isSpanish: isSpanish)
        }

        // 3. Date input kind or date canonical paths
        if question.inputKind == .date
            || question.canonicalPath.rawValue.lowercased().contains("date")
            || question.canonicalPath.rawValue.lowercased().contains(".dob")
            || question.englishFormLabel.lowercased().contains("date") {
            return validateDate(input: trimmed, isSpanish: isSpanish)
        }

        // 4. Name canonical paths
        if question.canonicalPath.rawValue.lowercased().contains("name.") {
            return validateName(input: trimmed, isSpanish: isSpanish)
        }

        // 5. City / Place canonical paths
        if question.canonicalPath.rawValue.lowercased().contains(".city")
            || question.canonicalPath.rawValue.lowercased().contains(".place") {
            return validateCity(input: trimmed, isSpanish: isSpanish)
        }

        // 6. Generic text with length bounds
        return validateText(input: trimmed, maxLength: question.maxLength, isSpanish: isSpanish)
    }

    // MARK: - Date Validation

    public static func validateDate(input: String, isSpanish: Bool) -> InterviewValidationResult {
        // Month names mapping
        let englishMonths: [String: Int] = [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9, "sept": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12
        ]

        let spanishMonths: [String: Int] = [
            "enero": 1, "ene": 1,
            "febrero": 2, "feb": 2,
            "marzo": 3, "mar": 3,
            "abril": 4, "abr": 4,
            "mayo": 5,
            "junio": 6, "jun": 6,
            "julio": 7, "jul": 7,
            "agosto": 8, "ago": 8,
            "septiembre": 9, "sep": 9, "setiembre": 9,
            "octubre": 10, "oct": 10,
            "noviembre": 11, "nov": 11,
            "diciembre": 12, "dic": 12
        ]

        var parsedMonth: Int?
        var parsedDay: Int?
        var parsedYear: Int?
        var rawCandidate: String = input

        let cleanInput = input
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try Pattern 1: ISO format YYYY-MM-DD or YYYY/MM/DD
        let isoRegex = try? NSRegularExpression(pattern: #"\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b"#)
        if let match = isoRegex?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
            if let yRange = Range(match.range(at: 1), in: input),
               let mRange = Range(match.range(at: 2), in: input),
               let dRange = Range(match.range(at: 3), in: input),
               let y = Int(input[yRange]),
               let m = Int(input[mRange]),
               let d = Int(input[dRange]) {
                parsedYear = y
                parsedMonth = m
                parsedDay = d
                if let fullRange = Range(match.range, in: input) {
                    rawCandidate = String(input[fullRange])
                }
            }
        }

        // Try Pattern 2: Numeric format M/D/YYYY, MM/DD/YYYY, M-D-YYYY, or DD/MM/YYYY
        if parsedMonth == nil {
            let numRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})\b"#)
            if let match = numRegex?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
                if let r1 = Range(match.range(at: 1), in: input),
                   let r2 = Range(match.range(at: 2), in: input),
                   let r3 = Range(match.range(at: 3), in: input),
                   let n1 = Int(input[r1]),
                   let n2 = Int(input[r2]),
                   var n3 = Int(input[r3]) {
                    if n3 < 100 {
                        // 2-digit year conversion
                        n3 += (n3 <= 30 ? 2000 : 1900)
                    }
                    parsedYear = n3
                    if let fullRange = Range(match.range, in: input) {
                        rawCandidate = String(input[fullRange])
                    }

                    if n1 > 12 && n2 <= 12 {
                        // Clearly DD/MM/YYYY (e.g. 25/01/2007)
                        parsedDay = n1
                        parsedMonth = n2
                    } else if n1 <= 12 && n2 > 12 {
                        // Clearly MM/DD/YYYY (e.g. 01/25/2007 or 01/32/2007)
                        parsedMonth = n1
                        parsedDay = n2
                    } else if isSpanish && n1 <= 31 && n2 <= 12 {
                        // In Spanish context, default to DD/MM/YYYY
                        parsedDay = n1
                        parsedMonth = n2
                    } else {
                        // Default US Immigration format: MM/DD/YYYY
                        parsedMonth = n1
                        parsedDay = n2
                    }
                }
            }
        }

        // Try Pattern 3: Textual Month (e.g., "January 15 2007", "15 de enero de 2007", "Jan 15, 2007")
        if parsedMonth == nil {
            let lowerTokens = cleanInput.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            var foundMonth: Int?
            var foundDay: Int?
            var foundYear: Int?

            for token in lowerTokens {
                let cleanToken = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if let m = englishMonths[cleanToken] ?? spanishMonths[cleanToken] {
                    foundMonth = m
                    continue
                }
                // Check if number
                let digitsOnly = cleanToken.filter(\.isNumber)
                if let num = Int(digitsOnly) {
                    if num >= 1900 && num <= 2100 {
                        foundYear = num
                    } else if num >= 1 && num <= 31 && foundDay == nil {
                        foundDay = num
                    }
                }
            }

            if let fm = foundMonth, let fy = foundYear {
                parsedMonth = fm
                parsedYear = fy
                parsedDay = foundDay ?? 1 // Default to 1st if only month/year provided
                rawCandidate = input
            }
        }

        // If no date components found at all
        guard let month = parsedMonth, let day = parsedDay, let year = parsedYear else {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "No se pudo reconocer una fecha válida. Por favor ingrese la fecha en formato MM/DD/AAAA (por ejemplo, 01/15/2007)."
                    : "I couldn't find a valid date in your answer. Please provide the date in MM/DD/YYYY format (for example, 01/15/2007).",
                rawCandidate: input
            )
        }

        // Calendar verification
        let monthNamesEn = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let monthNamesEs = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

        if month < 1 || month > 12 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "El mes \(month) no es válido. Los meses deben estar entre 1 y 12."
                    : "Month \(month) is not valid. Months must be between 1 and 12.",
                rawCandidate: rawCandidate
            )
        }

        let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        let daysInMonth = [0, 31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let maxDays = daysInMonth[month]

        if day < 1 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "El día no puede ser 0. Por favor ingrese un día válido."
                    : "The day cannot be 0. Please provide a valid day.",
                rawCandidate: rawCandidate
            )
        }

        if day > maxDays {
            let mName = isSpanish ? monthNamesEs[month] : monthNamesEn[month]
            if month == 2 && day == 29 && !isLeap {
                return .invalid(
                    rejectionPrompt: isSpanish
                        ? "El año \(year) no fue bisiesto, por lo que febrero solo tuvo 28 días. Por favor ingrese una fecha válida en formato MM/DD/AAAA."
                        : "February only had 28 days in \(year) because it was not a leap year. Please provide a valid date in MM/DD/YYYY format.",
                    rawCandidate: rawCandidate
                )
            } else {
                return .invalid(
                    rejectionPrompt: isSpanish
                        ? "\(mName.capitalized) solo tiene \(maxDays) días. La fecha '\(rawCandidate)' no existe en el calendario. Por favor ingrese una fecha válida (ej. 01/15/2007)."
                        : "\(mName) only has \(maxDays) days. The date '\(rawCandidate)' is not a valid calendar date. Please provide a valid date (for example, 01/15/2007).",
                    rawCandidate: rawCandidate
                )
            }
        }

        if year < 1900 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "El año \(year) es demasiado antiguo para este formulario. Por favor verifique el año."
                    : "Year \(year) is too far in the past for this form. Please verify the year.",
                rawCandidate: rawCandidate
            )
        }

        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        if year > currentYear + 1 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "La fecha no puede estar en el futuro (\(year)). Por favor ingrese una fecha válida."
                    : "The date cannot be in the future (\(year)). Please provide a valid date.",
                rawCandidate: rawCandidate
            )
        }

        // Format to standardized MM/DD/YYYY
        let normalized = String(format: "%02d/%02d/%04d", month, day, year)
        return .valid(normalizedValue: normalized)
    }

    // MARK: - Name Validation

    public static func validateName(input: String, isSpanish: Bool) -> InterviewValidationResult {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove conversational prefixes like "My last name is Gomez", "He is Carlos"
        let lower = cleaned.lowercased()
        let prefixes = [
            "my last name is", "my family name is", "my name is", "his last name is", "her last name is",
            "last name is", "family name is", "name is", "mi apellido es", "su apellido es", "el apellido es", "es"
        ]
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let startIdx = cleaned.index(cleaned.startIndex, offsetBy: prefix.count)
                cleaned = String(cleaned[startIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;\"'"))

        // Check that name contains letters
        let letterCount = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digitCount = cleaned.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count

        if letterCount < 2 || digitCount > 0 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "Un nombre o apellido debe contener letras válidas y no puede tener números. Por favor ingréselo de nuevo."
                    : "A name must contain valid letters and cannot contain numbers. Please provide the name again.",
                rawCandidate: input
            )
        }

        // Capitalize words properly
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let capitalized = words.map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")

        return .valid(normalizedValue: capitalized)
    }

    // MARK: - City / Place Validation

    public static func validateCity(input: String, isSpanish: Bool) -> InterviewValidationResult {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = cleaned.lowercased()
        let prefixes = [
            "born in", "in the city of", "in", "nació en", "en la ciudad de", "en", "fue en"
        ]
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let startIdx = cleaned.index(cleaned.startIndex, offsetBy: prefix.count)
                cleaned = String(cleaned[startIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;\"'"))

        let letterCount = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digitCount = cleaned.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count

        if letterCount < 2 || digitCount > 0 {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "El nombre de la ciudad o pueblo debe contener letras. Por favor ingrese la ciudad de nuevo."
                    : "A city or town name must contain letters and cannot be purely numbers or symbols. Please provide the city name again.",
                rawCandidate: input
            )
        }

        let words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let formatted = words.map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")

        return .valid(normalizedValue: formatted)
    }

    // MARK: - Choice Validation

    public static func validateChoice(input: String, choices: [String], isSpanish: Bool) -> InterviewValidationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = choices.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .valid(normalizedValue: match)
        }
        let listStr = choices.joined(separator: ", ")
        return .invalid(
            rejectionPrompt: isSpanish
                ? "Por favor elija una de las siguientes opciones: \(listStr)."
                : "Please choose one of the following options: \(listStr).",
            rawCandidate: input
        )
    }

    // MARK: - Yes/No Validation

    public static func validateYesNo(input: String, isSpanish: Bool) -> InterviewValidationResult {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let yesSet: Set<String> = ["yes", "y", "yeah", "yep", "true", "si", "sí", "s", "claro", "por supuesto"]
        let noSet: Set<String> = ["no", "n", "nope", "false", "negativo", "nunca"]

        if yesSet.contains(lower) {
            return .valid(normalizedValue: isSpanish ? "Sí" : "Yes")
        }
        if noSet.contains(lower) {
            return .valid(normalizedValue: "No")
        }

        return .invalid(
            rejectionPrompt: isSpanish
                ? "Por favor responda 'Sí' o 'No'."
                : "Please answer 'Yes' or 'No'.",
            rawCandidate: input
        )
    }

    // MARK: - Generic Text Validation

    public static func validateText(input: String, maxLength: Int?, isSpanish: Bool) -> InterviewValidationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "La respuesta no puede estar vacía. Por favor ingrese su información."
                    : "Answer cannot be empty. Please provide the required information.",
                rawCandidate: nil
            )
        }
        if let max = maxLength, trimmed.count > max {
            return .invalid(
                rejectionPrompt: isSpanish
                    ? "La respuesta excede el límite de \(max) caracteres. Por favor escriba una respuesta más breve."
                    : "Answer exceeds the maximum length of \(max) characters. Please provide a shorter answer.",
                rawCandidate: trimmed
            )
        }
        return .valid(normalizedValue: trimmed)
    }
}
