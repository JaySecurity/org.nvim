describe("utils._input_complete", function()
  local utils = require("org.utils")

  after_each(function()
    utils._complete_candidates = nil
  end)

  it("completes the last word from a candidate list", function()
    utils._complete_candidates = { "work", "home", "workshop" }
    eq({ "a:work", "a:workshop" }, utils._input_complete("wo", "a:wo", 0))
  end)

  it("passes the typed text to a candidate function", function()
    local seen
    utils._complete_candidates = function(text)
      seen = text
      return { "alpha", "beta" }
    end
    eq({ "beta" }, utils._input_complete("b", "b", 0))
    eq("b", seen)
  end)

  it("offers nothing when the candidate function returns nil", function()
    utils._complete_candidates = function()
      return nil
    end
    eq({}, utils._input_complete("x", "x", 0))
  end)

  it("offers nothing without candidates", function()
    eq({}, utils._input_complete("x", "x", 0))
  end)
end)
