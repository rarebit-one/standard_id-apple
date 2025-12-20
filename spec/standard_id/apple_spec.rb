# frozen_string_literal: true

RSpec.describe StandardId::Apple do
  it "has a version number" do
    expect(StandardId::Apple::VERSION).not_to be nil
  end
end
