import Foundation

enum SampleData {
    static let eventSuggestions = [
        "TechCrunch Disrupt 2026",
        "SaaStr Annual",
        "Web Summit",
        "Config 2026",
        "Next.js Conf"
    ]

    static let connections: [ConnectionProfile] = [
        ConnectionProfile(
            id: "maya",
            name: "Maya Rodriguez",
            headline: "VP Engineering at Notion",
            initials: "MR",
            colorHex: "FF5E3A",
            connectedAtLabel: "March 2023",
            yearsExperience: 12,
            yearsAtCurrentCompany: 3,
            bio: "PLG operator. Scaled growth at Notion, now building the next generation of collaborative engineering teams.",
            sharedEvents: [
                SharedEvent(name: "Notion Make Conference 2024", dateLabel: "Oct 2024"),
                SharedEvent(name: "Config 2023", dateLabel: "Jun 2023")
            ],
            mapX: 0.28,
            mapY: 0.32
        ),
        ConnectionProfile(
            id: "david",
            name: "David Kim",
            headline: "Founder & CEO at Vercel",
            initials: "DK",
            colorHex: "4F46E5",
            connectedAtLabel: "August 2021",
            yearsExperience: 15,
            yearsAtCurrentCompany: 6,
            bio: "Founder focused on developer experience, edge infrastructure, and fast product teams.",
            sharedEvents: [
                SharedEvent(name: "Next.js Conf 2024", dateLabel: "Oct 2024")
            ],
            mapX: 0.68,
            mapY: 0.24
        ),
        ConnectionProfile(
            id: "priya",
            name: "Priya Sharma",
            headline: "Senior PM at Stripe",
            initials: "PS",
            colorHex: "EC4899",
            connectedAtLabel: "February 2024",
            yearsExperience: 7,
            yearsAtCurrentCompany: 2,
            bio: "Product leader for payments infrastructure, developer platforms, and financial tooling.",
            sharedEvents: [
                SharedEvent(name: "Stripe Sessions 2025", dateLabel: "May 2025")
            ],
            mapX: 0.42,
            mapY: 0.56
        ),
        ConnectionProfile(
            id: "marcus",
            name: "Marcus Johnson",
            headline: "Partner at Andreessen Horowitz",
            initials: "MJ",
            colorHex: "10B981",
            connectedAtLabel: "June 2022",
            yearsExperience: 18,
            yearsAtCurrentCompany: 4,
            bio: "Investor in AI-native tools, infrastructure, and teams with unusually sharp product instincts.",
            sharedEvents: [
                SharedEvent(name: "a16z Summit", dateLabel: "Nov 2024"),
                SharedEvent(name: "Founders Forum 2024", dateLabel: "Jun 2024"),
                SharedEvent(name: "TED 2023", dateLabel: "Apr 2023")
            ],
            mapX: 0.77,
            mapY: 0.55
        ),
        ConnectionProfile(
            id: "elena",
            name: "Elena Vasquez",
            headline: "Principal Designer at Airbnb",
            initials: "EV",
            colorHex: "F59E0B",
            connectedAtLabel: "November 2023",
            yearsExperience: 11,
            yearsAtCurrentCompany: 5,
            bio: "Designs systems for high-trust marketplace experiences and teaches product storytelling.",
            sharedEvents: [
                SharedEvent(name: "Config 2024", dateLabel: "Jun 2024"),
                SharedEvent(name: "Awwwards Conference", dateLabel: "Feb 2024")
            ],
            mapX: 0.22,
            mapY: 0.72
        ),
        ConnectionProfile(
            id: "jordan",
            name: "Jordan Lee",
            headline: "Engineering Manager at Linear",
            initials: "JL",
            colorHex: "8B5CF6",
            connectedAtLabel: "January 2025",
            yearsExperience: 9,
            yearsAtCurrentCompany: 2,
            bio: "Leads product engineering teams that care about craft, velocity, and calm collaboration.",
            sharedEvents: [
                SharedEvent(name: "Linear Launch Week", dateLabel: "Mar 2025")
            ],
            mapX: 0.58,
            mapY: 0.76
        ),
        ConnectionProfile(
            id: "sofia",
            name: "Sofia Martinez",
            headline: "Head of Growth at Figma",
            initials: "SM",
            colorHex: "EF4444",
            connectedAtLabel: "September 2022",
            yearsExperience: 10,
            yearsAtCurrentCompany: 3,
            bio: "Growth strategist connecting community, enterprise adoption, and thoughtful activation.",
            sharedEvents: [
                SharedEvent(name: "Config 2024", dateLabel: "Jun 2024"),
                SharedEvent(name: "SaaStr Annual", dateLabel: "Sep 2023")
            ],
            mapX: 0.36,
            mapY: 0.84
        ),
        ConnectionProfile(
            id: "aiden",
            name: "Aiden Park",
            headline: "DevRel Lead at Supabase",
            initials: "AP",
            colorHex: "06B6D4",
            connectedAtLabel: "July 2024",
            yearsExperience: 6,
            yearsAtCurrentCompany: 1,
            bio: "Builder of developer communities, demos, and docs that make hard things feel approachable.",
            sharedEvents: [
                SharedEvent(name: "Supabase Launch Week 12", dateLabel: "Dec 2024")
            ],
            mapX: 0.72,
            mapY: 0.84
        )
    ]
}
