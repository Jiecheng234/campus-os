/**
 * Platform-aware SafeAreaView component.
 *
 * On Android/iOS: re-exports react-native-safe-area-context SafeAreaView
 * On HarmonyOS: uses View with padding (ArkUI handles safe areas natively)
 */

import React from 'react';
import { View, StyleSheet, Platform } from 'react-native';
import type { ViewProps, ViewStyle } from 'react-native';
import { isHarmonyOS } from '../app/platform';

interface SafeAreaViewProps extends ViewProps {
  children: React.ReactNode;
  edges?: ('top' | 'bottom' | 'left' | 'right')[];
}

let RNSafeAreaView: React.ComponentType<SafeAreaViewProps> | null = null;

function getSafeAreaView(): React.ComponentType<SafeAreaViewProps> {
  if (RNSafeAreaView) {
    return RNSafeAreaView;
  }

  try {
    const SafeArea = require('react-native-safe-area-context');
    RNSafeAreaView = SafeArea.SafeAreaView;
  } catch {
    RNSafeAreaView = HarmonySafeAreaView;
  }

  return RNSafeAreaView;
}

const HARMONY_SAFE_PADDING = Platform.select({
  default: { top: 44, bottom: 34, left: 0, right: 0 },
});

function HarmonySafeAreaView(props: SafeAreaViewProps): React.JSX.Element {
  const { style, edges, children, ...rest } = props;
  const padding: ViewStyle = {};

  if (!edges || edges.includes('top')) {
    padding.paddingTop = HARMONY_SAFE_PADDING.top;
  }
  if (!edges || edges.includes('bottom')) {
    padding.paddingBottom = HARMONY_SAFE_PADDING.bottom;
  }
  if (!edges || edges.includes('left')) {
    padding.paddingLeft = HARMONY_SAFE_PADDING.left;
  }
  if (!edges || edges.includes('right')) {
    padding.paddingRight = HARMONY_SAFE_PADDING.right;
  }

  return (
    <View style={[padding, style]} {...rest}>
      {children}
    </View>
  );
}

export function SafeAreaView(props: SafeAreaViewProps): React.JSX.Element {
  if (isHarmonyOS()) {
    return <HarmonySafeAreaView {...props} />;
  }

  const Component = getSafeAreaView();
  return <Component {...props} />;
}
