import React from 'react';
import LandingSection from '../features/launchpad/components/LandingSection';
import DexSelectorModal from '../features/launchpad/components/DexSelectorModal';

export default function LaunchpadPage({ launchSession, onDexSelected }) {
  const {
    isLaunched,
    isDexSelectorOpen,
    launch,
    chooseDex,
    closeDexSelector,
    selectedDex,
    pushToast,
  } = launchSession;

  return (
    <div className="relative min-h-[72vh]">
      <LandingSection
        isLaunched={isLaunched}
        onLaunch={() => {
          launch();
          pushToast('Launcher activated', 'Choose a DEX to open secure runtime page');
        }}
      />

      <DexSelectorModal
        isOpen={isDexSelectorOpen}
        onClose={closeDexSelector}
        onChoose={(dexId) => {
          chooseDex(dexId);
          onDexSelected?.();
          pushToast('DEX selected', 'DEX runtime page is ready');
        }}
      />

      {selectedDex ? (
        <div className="fixed bottom-4 left-4 z-[100] rounded-lg border border-brand-cyan/30 bg-black/70 px-3 py-2 text-[11px] uppercase tracking-[0.14em] text-brand-cyan">
          Active runtime: {selectedDex.name} ({selectedDex.chain})
        </div>
      ) : null}
    </div>
  );
}
