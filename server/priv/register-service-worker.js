const registerServiceWorker = async () => {
  if (!("serviceWorker" in navigator)) {
    console.warn("Service workers not available.");
    return;
  }

  try {
    const registration = await navigator.serviceWorker.register(
      "/static/service-worker.js",
      {
        scope: "/",
      },
    );
    if (registration.installing) {
      console.log("Service worker installing");
    } else if (registration.waiting) {
      console.log("Service worker installed");
    } else if (registration.active) {
      console.log("Service worker active");
    }
  } catch (err) {
    console.error(`Failed to register service worker`, err);
  }
};
registerServiceWorker();
