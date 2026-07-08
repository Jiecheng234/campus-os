/**
 * Platform-aware Markdown component.
 *
 * On Android/iOS: uses react-native-markdown-display
 * On HarmonyOS: renders as plain Text component
 */

import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { isHarmonyOS } from '../../app/platform';

interface MarkdownProps {
  children?: string;
  style?: object;
}

let RNMarkdown: React.ComponentType<MarkdownProps> | null = null;

function getRNMarkdown(): React.ComponentType<MarkdownProps> {
  if (RNMarkdown) {
    return RNMarkdown;
  }

  try {
    RNMarkdown = require('react-native-markdown-display').default;
  } catch {
    RNMarkdown = PlainTextMarkdown;
  }

  return RNMarkdown;
}

function PlainTextMarkdown(props: MarkdownProps): React.JSX.Element {
  return (
    <View style={props.style}>
      <Text>{props.children ?? ''}</Text>
    </View>
  );
}

export function Markdown(props: MarkdownProps): React.JSX.Element {
  if (isHarmonyOS()) {
    return <PlainTextMarkdown {...props} />;
  }

  const Component = getRNMarkdown();
  return <Component {...props} />;
}

export default Markdown;
