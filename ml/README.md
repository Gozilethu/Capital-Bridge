# ML Layer

The current AI verification sidecar is cloned at:

```text
../InvoiceCheck/
```

It is kept there for this local workspace because Windows denied moving the cloned directory after the service environment was created. The app and docs reference that current location.

For a clean repository layout later, move or reclone that project into:

```text
ml/InvoiceCheck/
```

Then update `package.json` and `docs/ai-model-integration.md` to use the new path.
