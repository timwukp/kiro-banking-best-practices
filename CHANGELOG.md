# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.2] - 2026-02-28

### Added
- **PDPA Compliance**: Personal Data Protection Act (Singapore) coverage with Kiro-specific controls
- **MAS Outsourcing Guidelines**: Third-party risk assessment for Kiro as AWS-managed service
- **MAS FEAT Principles**: AI/ML governance framework for AI-assisted development
- **ABS Guidelines References**: Cloud computing, penetration testing, and red team standards
- **Expanded TRM Mapping**: Deeper cross-references to specific MAS TRM sub-sections
- **CHANGELOG.md**: Version tracking for documentation changes
- **Approved MCP Server Tiers**: Added to README.md (previously only in quick reference)
- **Version History Table**: Added to README.md

### Changed
- **README.md**: Enhanced with MCP server tiers, expanded regulatory references, version history
- **README-Kiro-Banking-Best-Practices.md**: Converted from duplicate overview to concise quick-reference card
- **validate-repo.sh**: Enhanced with 8 validation checks (was 6), including broken links, secrets scanning, TODO detection, large file warnings, markdown structure
- **Part 2 Status**: Corrected from "In Progress" to "Complete"

### Removed
- Duplicate License/Disclaimer text from Kiro-Agentic-SDLC-Banking-Best-Practices.md and Kiro-Banking-Best-Practices-Part2.md (now reference LICENSE file)
- Content duplication between README.md and README-Kiro-Banking-Best-Practices.md

---

## [1.1] - 2026-02-26

### Added
- README.md with project overview, architecture diagrams, and documentation structure
- Updated .gitignore to exclude .vscode config files

---

## [1.0] - 2026-02-25

### Added
- Initial release: AWS Kiro Banking Best Practices for MAS-compliant SDLC
- Kiro-Agentic-SDLC-Banking-Best-Practices.md (Sections 1-4: Architecture, Identity, Network, VDI)
- Kiro-Banking-Best-Practices-Part2.md (Sections 5-10: MCP, SDLC, Data Protection, Compliance, Operations, Incident Response)
- Banking-Skills-Development-Guide.md (Kiro Skills for banking)
- kiro-docs/ technical reference (MCP configuration, security, servers, usage, privacy)
- validate-repo.sh validation script
- MIT License
- CONTRIBUTING.md guidelines
