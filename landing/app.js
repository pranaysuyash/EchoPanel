const WAITLIST_ENDPOINT = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec";

const forms = document.querySelectorAll("[data-waitlist]");

async function submitWaitlist(form) {
  const status = form.querySelector("[data-form-status]");
  status.textContent = "Submitting…";

  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());
  payload.timestamp = new Date().toISOString();
  payload.page = window.location.href;

  try {
    const response = await fetch(WAITLIST_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`Request failed: ${response.status}`);
    }

    status.textContent = "You are on the list. Check your inbox soon.";
    form.reset();
  } catch (error) {
    status.textContent = "Something went wrong. Please try again.";
    console.error(error);
  }
}

forms.forEach((form) => {
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    submitWaitlist(form);
  });
});
