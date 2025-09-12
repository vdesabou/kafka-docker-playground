import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export interface ContainerInfo {
  name: string;
  image: string;
  status: string;
  id: string;
}

export class DockerInspector {
  async getContainers(pattern?: string): Promise<string[]> {
    try {
      const { stdout } = await execAsync('docker ps --format "{{.Names}}"');
      let containers = stdout.trim().split('\n').filter(name => name.length > 0);
      
      if (pattern) {
        const regex = new RegExp(pattern, 'i');
        containers = containers.filter(name => regex.test(name));
      }
      
      return containers.sort();
    } catch (error) {
      console.error('Error getting Docker containers:', error);
      return [];
    }
  }

  async getDetailedContainers(pattern?: string): Promise<ContainerInfo[]> {
    try {
      const { stdout } = await execAsync(
        'docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}|{{.ID}}"'
      );
      
      let containers = stdout
        .trim()
        .split('\n')
        .filter(line => line.length > 0)
        .map(line => {
          const [name, image, status, id] = line.split('|');
          return { name, image, status, id };
        });
      
      if (pattern) {
        const regex = new RegExp(pattern, 'i');
        containers = containers.filter(container => regex.test(container.name));
      }
      
      return containers.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      console.error('Error getting detailed Docker containers:', error);
      return [];
    }
  }

  async getKafkaRelatedContainers(): Promise<string[]> {
    const containers = await this.getContainers();
    
    // Filter for containers that are likely Kafka-related
    const kafkaKeywords = [
      'kafka', 'zookeeper', 'connect', 'schema-registry', 
      'ksqldb', 'broker', 'control-center', 'rest-proxy'
    ];
    
    return containers.filter(name => 
      kafkaKeywords.some(keyword => 
        name.toLowerCase().includes(keyword)
      )
    );
  }

  async getConnectContainers(): Promise<string[]> {
    const containers = await this.getContainers();
    return containers.filter(name => 
      name.toLowerCase().includes('connect')
    );
  }

  async isContainerRunning(containerName: string): Promise<boolean> {
    try {
      const { stdout } = await execAsync(
        `docker ps --filter "name=${containerName}" --format "{{.Names}}"`
      );
      return stdout.trim().split('\n').some(name => name === containerName);
    } catch (error) {
      return false;
    }
  }

  async getContainerLogs(containerName: string, lines: number = 100): Promise<string> {
    try {
      const { stdout } = await execAsync(
        `docker logs --tail ${lines} ${containerName}`
      );
      return stdout;
    } catch (error) {
      throw new Error(`Failed to get logs for container ${containerName}: ${error}`);
    }
  }
}