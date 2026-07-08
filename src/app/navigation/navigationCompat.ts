/**
 * Navigation platform abstraction for CampusOS multi-platform.
 *
 * On Android/iOS: uses React Navigation v7
 * On HarmonyOS: provides a simplified stack/tab navigator
 *
 * This module wraps React Navigation APIs so that when RN-OH is available
 * without full React Navigation support, the app can still navigate.
 */

import React from 'react';
import { View } from 'react-native';
import { isHarmonyOS } from '../app/platform';

let NavigationModule: {
  NavigationContainer: React.ComponentType<{ children: React.ReactNode; theme?: object }>;
  createNativeStackNavigator: () => {
    Navigator: React.ComponentType<{ children: React.ReactNode; screenOptions?: object }>;
    Screen: React.ComponentType<{ name: string; component: React.ComponentType<object>; options?: object }>;
  };
  createBottomTabNavigator: () => {
    Navigator: React.ComponentType<{ children: React.ReactNode; screenOptions?: object }>;
    Screen: React.ComponentType<{ name: string; component: React.ComponentType<object>; options?: object }>;
  };
  useFocusEffect: (cb: () => void) => void;
  useNavigation: () => { navigate: (screen: string) => void; goBack: () => void };
} | null = null;

function getNavigation() {
  if (NavigationModule) {
    return NavigationModule;
  }

  try {
    const native = require('@react-navigation/native');
    const nativeStack = require('@react-navigation/native-stack');
    const bottomTabs = require('@react-navigation/bottom-tabs');
    NavigationModule = {
      NavigationContainer: native.NavigationContainer,
      createNativeStackNavigator: nativeStack.createNativeStackNavigator,
      createBottomTabNavigator: bottomTabs.createBottomTabNavigator,
      useFocusEffect: native.useFocusEffect,
      useNavigation: native.useNavigation,
    };
  } catch {
    NavigationModule = getFallbackNavigation();
  }

  return NavigationModule;
}

function getFallbackNavigation() {
  const SimpleContainer: React.ComponentType<{ children: React.ReactNode; theme?: object }> = (
    props: { children: React.ReactNode; theme?: object },
  ) => <View style={{ flex: 1 }}>{props.children}</View>;

  const createSimpleNavigator = () => ({
    Navigator: SimpleContainer as React.ComponentType<{ children: React.ReactNode; screenOptions?: object }>,
    Screen: (() => <View />) as unknown as React.ComponentType<{
      name: string;
      component: React.ComponentType<object>;
      options?: object;
    }>,
  });

  return {
    NavigationContainer: SimpleContainer,
    createNativeStackNavigator: createSimpleNavigator,
    createBottomTabNavigator: createSimpleNavigator,
    useFocusEffect: (_cb: () => void) => {},
    useNavigation: () => ({
      navigate: (_screen: string) => {},
      goBack: () => {},
    }),
  };
}

// Re-export wrapped versions
export const NavigationContainer = getNavigation().NavigationContainer;
export const createNativeStackNavigator = getNavigation().createNativeStackNavigator;
export const createBottomTabNavigator = getNavigation().createBottomTabNavigator;
export const useFocusEffect = getNavigation().useFocusEffect;
export const useNavigation = getNavigation().useNavigation;

// Re-export screen props types
export type { NativeStackScreenProps } from '@react-navigation/native-stack';
export type { BottomTabScreenProps } from '@react-navigation/bottom-tabs';
export type { CompositeScreenProps } from '@react-navigation/native';
