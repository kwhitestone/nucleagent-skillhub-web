# Skill Hub Web

Independent Vue application for project discovery, cloud recipes and a human review queue. The server owns catalog metadata, immutable releases, provenance and audit state. Published releases open the shell's TaskSetup deep link; this application is not a shell remote or iframe addon.

Run `npm ci` in `admin/`, then `npx eslint src types --ext .js,.ts,.vue --max-warnings 0`, `npx vue-tsc --noEmit` and `npm run build`.

The container requires `API_UPSTREAM`, `SHELL_ORIGIN` and `FRAME_ANCESTORS`. Origins are deployment inputs; no deployment domain is compiled into source. API requests are same-origin through nginx. The API supplies the approved shell origin. Frame ancestors are exact HTTPS origins separated by commas.

Operator keys are entered in the review workspace and retained only in page memory. Refresh clears them. Public visitors can browse and open published releases; generating cloud artifacts and changing records require an operator. This P0 does not introduce an Auth login contract.

Ecosystem names indicate inspiration for original recipes, not verification or bundling of upstream projects. Dry runs validate structure and parameters only. Channel availability and actual upstream compatibility require separate live acceptance.
