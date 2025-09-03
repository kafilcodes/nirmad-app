/*
  Firebase Messaging Service Worker (Web)
  - Required for background notifications and to satisfy service worker registration.
  - Uses a generic push handler so you get notifications without hardcoding config here.
  - If you want full Firebase Messaging features (like handling data-only messages),
    uncomment the importScripts + firebase.initializeApp below and fill the public web config.
*/

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

// Optional: Enable Firebase Messaging inside the worker (requires public web config)
// importScripts('https://www.gstatic.com/firebasejs/9.6.11/firebase-app-compat.js');
// importScripts('https://www.gstatic.com/firebasejs/9.6.11/firebase-messaging-compat.js');
// firebase.initializeApp({
//   apiKey: 'YOUR_API_KEY',
//   authDomain: 'YOUR_AUTH_DOMAIN',
//   projectId: 'YOUR_PROJECT_ID',
//   storageBucket: 'YOUR_STORAGE_BUCKET',
//   messagingSenderId: 'YOUR_SENDER_ID',
//   appId: 'YOUR_APP_ID',
//   measurementId: 'YOUR_MEASUREMENT_ID',
// });
// const messaging = firebase.messaging();

// Fallback handler for push events (works when notification payload is present)
self.addEventListener('push', (event) => {
  try {
    const data = event.data ? event.data.json() : {};
    const title = data.notification?.title || data.title || 'Notification';
    const body = data.notification?.body || data.body || '';
    const icon = data.notification?.icon || '/icons/Icon-192.png';
    const link = data.fcmOptions?.link || data.notification?.click_action || data.click_action || '/';
    event.waitUntil(self.registration.showNotification(title, { body, icon, data: { link, ...data } }));
  } catch (e) {
    // If parsing fails, show a generic message to avoid silent failures
    event.waitUntil(self.registration.showNotification('Notification', { body: '' }));
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification?.data?.link || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
