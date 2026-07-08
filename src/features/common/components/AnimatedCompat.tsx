/**
 * Platform-aware Animated components.
 *
 * On Android/iOS: uses react-native-reanimated (FadeInDown, useSharedValue, etc.)
 * On HarmonyOS: falls back to RN Animated API (no Worklet support)
 */

import React from 'react';
import { Animated as RNAnimated, View } from 'react-native';
import type { ViewProps } from 'react-native';
import { isHarmonyOS } from '../../app/platform';

let ReanimatedModule: {
  default: React.ComponentType<ViewProps>;
  FadeInDown: object;
  useSharedValue: (v: number) => { value: number };
  useAnimatedStyle: (cb: () => object) => object;
  withRepeat: (anim: object, count: number) => object;
  withTiming: (to: number, opts: object) => object;
  Easing: { linear: object };
} | null = null;

function getReanimated() {
  if (ReanimatedModule) {
    return ReanimatedModule;
  }

  try {
    ReanimatedModule = require('react-native-reanimated');
  } catch {
    ReanimatedModule = null;
  }

  return ReanimatedModule;
}

export function useAnimatedStyleCompat(cb: () => object): object {
  if (isHarmonyOS()) {
    return {};
  }
  const mod = getReanimated();
  if (mod) {
    return mod.useAnimatedStyle(cb);
  }
  return {};
}

export function useSharedValueCompat(v: number): { value: number } {
  if (isHarmonyOS()) {
    return { value: v };
  }
  const mod = getReanimated();
  if (mod) {
    return mod.useSharedValue(v);
  }
  return { value: v };
}

export const AnimatedView: React.ComponentType<ViewProps> = (props: ViewProps) => {
  if (isHarmonyOS()) {
    return <View {...props} />;
  }
  const mod = getReanimated();
  if (mod) {
    return <mod.default {...props} />;
  }
  return <RNAnimated.View {...props} />;
};

export const FadeInDown: object | undefined = isHarmonyOS() ? undefined :
  getReanimated()?.FadeInDown;

export const EasingLinear: object = {};

export function makeSkeletonAnimation(
  opacity: { value: number },
): { opacity: number } {
  if (isHarmonyOS()) {
    const anim = new RNAnimated.Value(0.3);
    RNAnimated.loop(
      RNAnimated.sequence([
        RNAnimated.timing(anim, {
          toValue: 0.7,
          duration: 800,
          useNativeDriver: true,
        }),
        RNAnimated.timing(anim, {
          toValue: 0.3,
          duration: 800,
          useNativeDriver: true,
        }),
      ]),
    ).start();
    return { opacity: anim as unknown as number };
  }
  return { opacity: opacity.value };
}
