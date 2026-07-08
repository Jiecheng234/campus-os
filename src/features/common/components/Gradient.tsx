/**
 * Platform-aware Gradient component.
 *
 * On Android/iOS: re-exports react-native-linear-gradient
 * On HarmonyOS: renders a simple View with background color (ArkUI gradient via native)
 */

import React from 'react';
import { View, StyleSheet, Platform } from 'react-native';
import type { ViewProps, ViewStyle } from 'react-native';
import { isHarmonyOS } from '../../app/platform';

interface GradientProps extends ViewProps {
  children?: React.ReactNode;
  colors: (string | number)[];
  start?: { x: number; y: number };
  end?: { x: number; y: number };
  locations?: number[];
}

let RNGradient: React.ComponentType<GradientProps> | null = null;

function getGradient(): React.ComponentType<GradientProps> {
  if (RNGradient) {
    return RNGradient;
  }

  try {
    RNGradient = require('react-native-linear-gradient').default;
  } catch {
    RNGradient = FallbackGradient;
  }

  return RNGradient;
}

function FallbackGradient(props: GradientProps): React.JSX.Element {
  const { colors, style, children, ...rest } = props;
  const bgColor: string | undefined = typeof colors[0] === 'string' ? colors[0] as string : undefined;

  return (
    <View style={[style, bgColor ? { backgroundColor: bgColor } : undefined]} {...rest}>
      {children}
    </View>
  );
}

export function LinearGradient(props: GradientProps): React.JSX.Element {
  if (isHarmonyOS()) {
    return <FallbackGradient {...props} />;
  }

  const Component = getGradient();
  return <Component {...props} />;
}

export default LinearGradient;
