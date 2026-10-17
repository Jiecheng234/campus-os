/**
 * Type declaration for hvigor's build-time generated BuildProfile module.
 *
 * The real module is generated into
 * entry/build/default/generated/profile/default/BuildProfile.ets and injected by
 * the build pipeline only; static analyzers that do not run hvigor cannot resolve
 * `import BuildProfile from 'BuildProfile'`. This declaration mirrors just the
 * member used by utils/Logger.ets (DEBUG) and does not affect the build output.
 */
declare module 'BuildProfile' {
  export const DEBUG: boolean;

  export default class BuildProfile {
    static readonly DEBUG: boolean;
  }
}
