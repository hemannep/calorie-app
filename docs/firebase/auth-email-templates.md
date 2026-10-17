# Kayleo authentication email templates

Firebase Authentication sends verification and password-recovery emails. Apply
the copy below in **Firebase Console → Authentication → Templates**. Replace the
bracketed values before launch.

## Production sender setup

- Sender name: `Kayleo`
- From address: `no-reply@[your-domain]`
- Reply-to address: `support@[your-domain]`
- Authentication email domain: `auth.[your-domain]`
- App name / OAuth consent brand: `Kayleo`

Configure the custom email domain and publish the DNS records shown by Firebase.
Use a custom action URL on the same branded domain so recipients do not land on
a `firebaseapp.com` page. Keep SPF, DKIM, and DMARC enabled for the sending
domain. Do not use a personal inbox as the From address.

## Email address verification

Subject:

```text
Verify your email for Kayleo
```

Body:

```text
Hello %DISPLAY_NAME%,

Welcome to Kayleo. Please verify this email address to finish creating your account and keep your nutrition data secure.

Verify my email: %LINK%

If you did not create a Kayleo account, you can safely ignore this message. This verification link is intended only for %EMAIL%.

Kayleo
Your day, in balance.
```

## Password reset

Subject:

```text
Reset your Kayleo password
```

Body:

```text
Hello,

We received a request to reset the password for %EMAIL%.

Reset my password: %LINK%

For your security, this link can only be used for this password-reset request. Kayleo will never ask you to send your password by email.

If you did not request a password reset, no action is needed and your password will remain unchanged.

Kayleo
Your day, in balance.
```

## Launch checks

1. Send both templates to Gmail, Outlook, and Apple Mail test accounts.
2. Confirm the sender name, reply-to address, links, mobile wrapping, and spam placement.
3. Confirm verification returns to the branded action page and the app accepts
   the newly verified session.
4. Confirm reset links reject expired or already-used action codes.
5. Never include health details, calorie targets, meal names, or other private
   account data in authentication emails.

Firebase's built-in templates have limited visual customization. For a fully
branded HTML email and action page, generate the Firebase action link on a
trusted server and send it through a transactional email provider; do not
generate or validate numeric OTP codes in the Flutter client.
