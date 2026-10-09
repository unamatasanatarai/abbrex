import Foundation

/// Unified default abbreviation dictionary library.
public struct DefaultLibrary {
    
    public static var defaultItems: [ExpansionPayload] {
        [
            ExpansionPayload(
                id: ":disc",
                prefix: ":disc",
                expansion: """
                --------------------------------------------------
                CONFIDENTIALITY NOTICE & LEGAL DISCLAIMER
                The contents of this document and any attachments are intended solely for the addressee.
                Created on {{date:YYYY-MM-DD}} at {{time}}. All rights reserved.
                --------------------------------------------------
                """
            ),
            ExpansionPayload(
                id: ":sig",
                prefix: ":sig",
                expansion: """
                Best regards,

                Senior Content Strategist & Copywriter
                Direct: +1 (555) 019-2834 | {{date}}
                """
            ),
            ExpansionPayload(
                id: "qa-bug",
                prefix: "qa-bug",
                expansion: """
                ## [BUG] 

                ### 📌 Description
                A brief description of the unexpected behavior encountered during testing.

                ### 🔄 Steps to Reproduce
                1. Navigate to dashboard or target component.
                2. Action performed: `{{clipboard}}`
                3. Observe system behavior.

                ### 🎯 Expected Result
                System should handle input gracefully without error or visual artifact.

                ### ❌ Actual Result
                Unexpected behavior occurs.

                ### 💻 Environment Matrix
                - **OS**: macOS 12+
                - **Timestamp**: {{date}} {{time}}
                """
            )
        ]
    }
}
