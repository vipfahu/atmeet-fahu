import { Button } from '@/components/ui/button';

export function InstitutionalBrand() {
  return (
    <a className="brand institutional-brand" href="/" aria-label="AtMeet FAHU · Ir al calendario">
      <img className="brand-logo" src="/fahu-logo.png" alt="Facultad de Humanidades · Universidad de Santiago de Chile" />
      <span className="brand-copy">
        <strong>AtMeet FAHU</strong>
        <span>Vicedecanato de Investigación y Postgrado · FAHU USACH</span>
      </span>
    </a>
  );
}

export function InstitutionalFooter() {
  return (
    <footer className="institutional-footer">
      <span>Vicedecanato de Investigación y Postgrado · Facultad de Humanidades · Universidad de Santiago de Chile</span>
      <a href="https://vipfahu.netlify.app">Portal Gestión de Información VIP <span aria-hidden="true">↗</span></a>
    </footer>
  );
}

export function ConsultationCard({ number, title, description, label, onClick }: {
  number: string;
  title: string;
  description: string;
  label: string;
  onClick: () => void;
}) {
  return (
    <Button className="consultation-card" aria-label={`${title}. ${label}`} onClick={onClick}>
      <span className="consultation-card-number" aria-hidden="true">{number}</span>
      <span className="consultation-card-title">{title}</span>
      <span className="consultation-card-description">{description}</span>
      <span className="consultation-card-action">Crear consulta <span aria-hidden="true">→</span></span>
    </Button>
  );
}
