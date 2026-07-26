# frozen_string_literal: true

# Idempotent demo seeds. Runs on every boot; creates nothing that already exists.
# Requires models.rb to have been loaded (needs Page and the Docsmith constants).

# An HTML document carrying a script tag, so /pages has something that actually
# demonstrates the difference between the html_sanitizer modes.
XSS_DEMO_HTML = <<~HTML.strip
  <h3>Quarterly Report</h3>
  <p>Revenue is <strong>up 12%</strong>. See the <a href="/details">details</a>.</p>
  <script>alert('this executes under :unsafe_raw')</script>
  <img src="x" onerror="alert('so does this')">
HTML

if Page.none?
  page = Page.create!(title: "Untrusted HTML Sample", body: XSS_DEMO_HTML)
  page.save_version!(author: User.first, summary: "Initial draft")

  page.update_column(:body, XSS_DEMO_HTML.sub("up 12%", "up 18%"))
  page.send(:_docsmith_document).update_column(:content, page.body)
  page.save_version!(author: User.first, summary: "Corrected the revenue figure")
end
