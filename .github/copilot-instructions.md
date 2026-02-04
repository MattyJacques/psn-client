The following instructions apply to all code generation and assistance for this project:

1. **RuboCop Compliance**: Ensure that no new RuboCop errors are introduced. Adhere strictly to the project's Ruby style guide and linting rules.
2. **Frozen String Literals**: All Ruby files must start with `# frozen_string_literal: true`.
3. **Test Coverage**: Always ensure there is adequate RSpec test coverage for any new functionality or bug fixes. Use `RSpec.describe` and the `expect(...)` syntax; do not use the `should` syntax.
4. **Type Signatures**: Update RBS signatures in `sig/` whenever method signatures change or new public methods are added.
5. **Documentation**: If public APIs are modified, update the relevant documentation and the `CHANGELOG.md` file.
